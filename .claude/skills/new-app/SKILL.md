---
name: new-app
description: Scaffold and wire up a new self-hosted application on the Proxmox docker host of this homelab — Ansible role, docker.yml registration, Borgmatic backup, and Pangolin routing/healthcheck/SSO via Tofu. Use when the user asks to add, deploy, or onboard a new app/service to the homelab.
---

# Deploy a new app on the homelab

Every app added to this repo touches the same ~7 files (verified against the
`gramps`, `homelable` and `flip_planning` additions). Skipping one is
the most common source of a "works but isn't backed up" or "deployed but
unreachable" app. Use `ansible/roles/trek` and
`ansible/roles/wishlist` as your primary reference implementations — they're
the freshest and match current conventions exactly (unlike some older roles).

Pick a service slug once and use it consistently: `snake_case` for Ansible
role/variable names, `kebab-case` for the Pangolin role slug in
`tofu/pangolin_config/roles.tf`.

## 1. Ansible role skeleton

Create `ansible/roles/<service>/` with `defaults/`, `handlers/`, `tasks/`,
`templates/` (mirror `ansible/roles/trek/`):

- `defaults/main.yml`: `<service>_base_path: "{{ docker_base_path }}/<service>"`
  plus the backup vars (see step 4).
- `templates/compose.yaml`: the container that must be publicly reachable
  joins the **external** `newt` network; anything DB/backend-only goes on an
  **internal**, service-named network only — never put a database on `newt`.
  Declare that network `internal: true` unless a container attached only to
  it needs the Internet. Databases, redis/valkey and meilisearch get a
  `healthcheck` (binary present in the image), dependents wait with
  `depends_on: {<db>: {condition: service_healthy}}`, and databases get
  `stop_grace_period: 60s` — details in « Conventions » below; the Molecule scenario
  lists them for `_shared/tasks/verify_compose_services.yml`.
  Container names matter: they're what the Pangolin target's `ip`/`hc_hostname`
  will reference in step 6.
  For image references, use a **concrete version tag** corresponding to the
  latest available release (for example `:3.4.1`), not the floating `:latest`
  tag and not a digest pin like `@sha256:...` unless the user explicitly asks.
  Renovate adds the digest afterwards (`pinDigests`) and bumps it: `dc@` only
  pulls the images that are missing, never refreshes a tag that is already
  there. An image that must follow a moving tag needs `pull_policy: always`
  on its service.
- `templates/env.j2` (or `env.docker.j2`): templated `.env`, mode `0600`.
- No borgmatic template in the role: every config is rendered by the
  `borgmatic` role (`tasks_from: app.yml`), the role only declares its
  sources and databases (see the `borgmatic-backup` skill).
- `tasks/main.yml`, in order: ensure app folders exist → template
  `compose.yaml` (mode `0600`: it often carries secrets; notify `Restart <service>`) → template env file → borgmatic
  `include_role` (`when: <service>_backup_enabled`, tags: `backup`) → `systemd: name=dc@<service> scope=user state=started enabled=true`.
- `handlers/main.yml`: a `Restart <service>` handler that
  `systemd: state=restarted name=dc@<service> scope=user daemon_reload=true`.

Don't template a bespoke `.service` file — `docker_service` already provides
the generic `dc@.service` unit; your role only needs to start/enable
`dc@<service>`.

If the app's data should live on the NAS rather than the VM's disk, follow
`ansible/roles/nas_storage/README.md` (`nas_storage` meta dependency, absolute
bind mounts, DB dump only, never SQLite on NFS).

## 2. Register the role in `ansible/docker.yml`

Two edits:
- In `pre_tasks` → `Load healthcheck URLs from Terraform state outputs`, add
  `<service>_backup_healthcheck_url: "{{ terraform_outputs.uptime_backup_<service>_url.value | default('') }}"`.
- In `roles:`, append `- role: <service>` / `tags: <service>,app`.

## 3. Backup folder registration

Nothing to register for a new app: Borg creates its repository on the first
`repo-create`, inside the subaccount folder of the host that runs it
(`backup/<host>/<service>` on the Storage Box; each host's subaccount only
sees its own folder). Only a new *host* needs registering: add it to
`backup_storage_box_hosts` (`ansible/host_vars/backups/variables.yaml`), to
`local.backup_hosts` (`tofu/pangolin/storage_box_subaccounts.tf`) and to the
SOPS key `backup_storage_box_subaccounts`, set `backup_storage_box_subaccount`
in its `host_vars`, then run `ansible-playbook backup.yaml`
once its borgmatic role has generated its key.

Do register the app in the restore test: an entry
`"<service>": {"host": "<host>", "repo": "<borgmatic_app_name>", "role": "<role>", "databases": ["<postgresql|mysql|sqlite>"]}`
in `.github/restore-test/apps.json` (`pangolin_config`'s `tofu test` fails
on any `backup = true` website missing from it; `databases` lists the kinds
of the role's `borgmatic_app_*_databases`, `[]` for none, checked by
`test_restore_test_databases.py`). Until its first nightly
archive exists, the next restore-test run fails on it with « aucune archive »;
an app whose SQLite file did not exist yet at deploy time (first start after
the deploy) gets no staged copy until the next deploy, and fails it with
« aucun dump ni copie sqlite »: redeploy once the app has started.

## 4. Backup vars

In the role's `defaults/main.yml` (nothing in `host_vars` unless a host must
override them):

```yaml
<service>_backup_enabled: true
<service>_backup_borgmatic_target: "{{ backup_storage_box_url }}/<service>"
<service>_backup_encryption_passphrase: "{{ backup_passphrase }}"
<service>_backup_healthcheck_url: ""
```

## 5. Secrets

If the service needs its own secret (DB password, admin password, API key),
add it to `secrets/ansible.sops.yaml` via `sops secrets/ansible.sops.yaml` (never hand-edit
the encrypted blob, never commit plaintext), and give the key its entry in
`secrets/secrets-rotation.yaml` (kind, `last_rotated`, procedure: the Lint workflow
fails on a SOPS key without one). Both live in the `secrets/` submodule: commit
there, push to `homelab-secrets`, then commit the submodule bump with the role
(`docs/conventions/secrets.md`). Remember: a variable loaded via
`community.sops.load_vars` (`return_method: vars-only`) lands in the
`include_vars` layer — it beats role defaults, `group_vars`/`host_vars`, play
`vars:`, role-entry `vars:`, a role's `vars/main.yml` and block/task `vars:`,
and loses only to `set_fact`/registered vars, role and include params
(`include_role` `vars:`) and extra vars. Never name a SOPS key after a
variable a playbook or role sets (`docs/conventions/secrets.md`).

Add every new secret key to `ansible/molecule/_shared/vars/fake_secrets.yml`
too, with a dummy value: the Molecule scenarios load it instead of SOPS, through
`_shared/tasks/load_fake_secrets.yml` (`include_vars`, same layer).

## 5b. Molecule scenario

Copy `ansible/molecule/trek/` to `ansible/molecule/<service>/` and adapt it
(scenario name, role, host_vars file, verify assertions). The `Tests` workflow
picks it up automatically; `mise run molecule <service>` runs it locally.

## 6. Pangolin routing

Delegate to the **pangolin-route** skill for `tofu/pangolin_config/roles.tf`
+ `tofu/pangolin_config/website_<service>.tf` (an entry of `local.websites`,
listed in `websites.tf`, which generates the resource, target and monitors).
Pay special attention to its
two documented pitfalls (missing `hc_hostname`, target `priority` ordering) —
both come from real bugs shipped in this repo.

## 7. Apply and deploy, in this order

Tofu must run first: `docker.yml` reads the Terraform state to populate the
backup healthcheck URL, so the resource needs to exist before the Ansible run.

```bash
cd tofu/pangolin_config && tofu fmt -recursive && tofu validate && tofu plan
tofu apply

cd ../../ansible
ansible-lint
ansible-playbook docker.yml --check --tags <service>,app
ansible-playbook docker.yml --tags <service>,app
```

Homepage only reads the `homepage_links` output when its role runs, and a
merge redeploys the roles whose files changed, not `homepage`: once
`pangolin_config` is applied, run `ansible-playbook docker.yml --tags homepage`
so the new app's link shows up.

## 8. Verify

```bash
systemctl --user status dc@<service>
journalctl --user -u dc@<service> -n 50
curl -I https://<subdomain>.sylvain.cloud   # or whatever full_domain you set
```

Check the new app's HTTP and backup-push monitors show up (and go healthy) in
Uptime Kuma.

## Known pitfalls (from real fix commits in this repo, not hypothetical)

- **Missing `hc_hostname`** on a `pangolin_target` silently breaks the
  healthcheck — it is not inferred from `ip`. Always set it explicitly.
- **`priority` ordering on multi-target routing is counter-intuitive**: for
  path-based sub-routes on the same resource (e.g. an admin UI under `/db`),
  the catch-all `"/"` target needs the **lowest** priority number and more
  specific paths need **higher** numbers — see `pangolin-route` for the full
  example.
- Compose file is always named `compose.yaml`, never `docker-compose.yml`.
- PUID/PGID (if the image needs them) come from `ansible_facts['user_uid']`/`user_gid'`, not hardcoded.
- Resource limits follow the doctrine in `docs/conventions/resource-limits.md`: `mem_limit` on every
  service (≈2× expected peak), `mem_reservation` on DBs, **no `cpus:`** except
  `cpus: 2.00` + `cpu_shares: 512` on batch workers. Check the image's default
  worker count fits under the cap.

## Conventions (the former « Adding a new app role » section of AGENTS.md)

The `homelab-reviewer` agent sanity-checks the resulting diff before `tofu apply`/`ansible-playbook`.

- **Public HTTP routing is entirely OpenTofu-managed, not Docker labels.** Each exposed app gets a `tofu/pangolin_config/website_<service>.tf` declaring its entry of `local.websites` (name, domain, role, target(s), backup flag, its `homepage` link or `homepage = null`: the `homepage_links` output, read by `docker.yml`, is the Homepage role's list of links) and its outputs; `websites.tf` turns every entry into the `pangolin_resource` + `pangolin_target` (+ SSO role binding + healthcheck access token + Uptime Kuma monitors) with `for_each`, so the pins, the maintenance page and the probe settings are written once — Newt reads Docker (through its `wollomatic/socket-proxy` sidecar: ping, container list, inspect of itself, events) only to report the container list Pangolin shows in its UI; no target is validated against it (newt 1.19.0: `IsWithinHostNetwork` is never called), and no `pangolin.public-resources.*` label is used (an earlier pattern, no longer used anywhere in this repo). The container must join the external `newt` Docker network (created by the `newt` role) for Pangolin to reach it. If the app has its own DB, put the DB on a second, internal, service-named network — never on `newt` — declared `internal: true` (no Internet route through it; the app keeps its own through `newt`) unless a container attached *only* to it needs the Internet: karakeep's crawler and immich's ML stay non-internal. Changing `internal` on an existing network: `docker compose up` recreates it only when it carries compose's config-hash label, and silently keeps a network created by an older compose as it was — run `docker compose down` once, then check `docker network inspect --format '{{.Internal}}' <network>`. A single-container app needs no private network at all. Two easy-to-miss details: every `pangolin_target` needs `hc_hostname` set explicitly (not inferred from `ip`; `websites.tf` sets it to `ip`, a hand-written target must set it), and multi-target path routing (`sub_targets`) needs the catch-all `"/"` at the *lowest* `priority` number, not the highest. Renaming an entry key or moving a resource into or out of the `for_each` needs a `moved` block, or its access token and push monitor are recreated.
- `compose.yaml` (and `.env`) are templated `0600`: they carry secrets, and `dc@` reads them as their owner. `verify_app.yml` asserts it. Every `template`/`copy` of a `0600` file also sets `diff: false`, and every `set_fact` of a push URL or token `no_log: true`: a `--diff` or `-v` run would otherwise write the secret to `ansible/run.log` and the CI logs.
- Databases, redis/valkey and meilisearch get a `healthcheck` whose binary exists in the image (`pg_isready`; `healthcheck.sh --connect` for the official mariadb image; `mariadb-admin ping --host=127.0.0.1` for linuxserver's, which has no `healthcheck.sh`; `redis-cli`/`valkey-cli ping`, with `-a "$$REDIS_PASSWORD"` when a password is set), and whatever needs them waits with `depends_on: {<db>: {condition: service_healthy}}`. Databases also get `stop_grace_period: 60s`: `dc@` stops with `docker compose stop`, whose 10 s default SIGKILLs them. Molecule checks all three through `_shared/tasks/verify_compose_services.yml`.
- Backups: `ansible/roles/borgmatic/README.md` (shared template rules, NAS container mode, one Storage Box subaccount per host) and the `borgmatic-backup` skill.
- Finally, add the role to the right playbook (`docker.yml` for the Proxmox host, `pangolin.yaml` for the Pangolin VM, etc.) with sensible tags (`<service>,app`), and wire its `<service>_backup_healthcheck_url` into that playbook's `pre_tasks` alongside the others.
- Pausing, a second environment, removal: `docs/conventions/app-lifecycle.md`.
