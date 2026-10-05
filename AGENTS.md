# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A personal homelab infrastructure-as-code project (French comments/docs, English code). It provisions and configures two deployment targets:

1. **Pangolin** — a Hetzner Cloud VM running Pangolin Zero Trust (Traefik-based reverse proxy / tunnel), provisioned by `tofu/pangolin` and configured by `ansible/pangolin.yaml`.
2. **Proxmox** — a local Docker VM (+ a Newt LXC container) provisioned by `tofu/proxmox` and configured by `ansible/docker.yml`, running all the self-hosted apps (Nextcloud, Immich, Paperless-ngx, Monica, Wiki.js-style wiki, RSS reader, SearXNG, Semaphore, Betisier, Meerkat CRM, Homelable, etc.).
3. **Flip** — a Hetzner Cloud VM with **no public IP** (private network only), provisioned by `tofu/pangolin/flip.tf` and configured by `ansible/flip.yml`, dedicated to Flip Planning (production + demo). Pangolin reaches it through the Newt running on it (site `flip`); it reaches the Internet through Pangolin, which NATs for the private network (`hcloud_network_route` in `tofu/pangolin/nat.tf`, roles `nat_gateway` on Pangolin and `nat_client` on flip).

There's also a Raspberry Pi (`ansible/pi.yml`, Immich) and a Hetzner Storage Box used purely as an Ansible group (`backups`) for remote backup folder provisioning.

Stack: **OpenTofu** (infra) → **Packer** (Pangolin base image) → **Ansible** (host config + app deploy via Docker Compose) → **SOPS/Age** (secrets) → **Borgmatic** (backups to Hetzner Storage Box).

## Commands

All commands run through **mise** (not make). Tool versions are pinned in `mise.toml`; run `mise install` once, then `uv sync` for the Python venv.

```bash
# OpenTofu — Pangolin target (tofu/pangolin)
mise run init            # tofu init
mise run plan            # tofu plan
mise run apply            # tofu apply

# OpenTofu — Proxmox target (tofu/proxmox)
mise run init-proxmox
mise run plan-proxmox
mise run apply-proxmox

# OpenTofu — ref.sylvain.dev (tofu/ref), GITHUB_TOKEN exporté avant
mise run init-ref
mise run plan-ref
mise run apply-ref

# OpenTofu linting (both targets)
mise run lint             # tofu fmt -check -recursive && tofu validate (both dirs)
mise run fix-lint          # tofu fmt -recursive

# Packer (Pangolin base image, in packer/pangolin)
mise run packer-init
mise run packer-validate
mise run packer-build      # requires HCLOUD_TOKEN

# Ansible (run from ansible/, or via mise which cd's there)
mise run ansible-lint
mise run ansible-run       # ansible-playbook -i inventory/hosts site.yml  (NOTE: no site.yml exists — target a real playbook explicitly instead, see below)
mise run ansible-check     # same, with --check

# Tests (see "Tests" below)
mise run molecule [role]   # Molecule scenario of one role (all when omitted); builds the test image first
mise run tofu-test         # tofu test of every tofu/<module> that has a tests/ dir

# Misc
mise run generate_password "<plain>"   # mkpasswd sha512 for a host user password
mise run get_state                     # dumps `tofu state pull` for the current dir to state.json
```

`mise run lint` only covers `tofu/pangolin` and `tofu/proxmox`; `tofu/pangolin_config` is covered by `mise run tofu-test` and by the `Lint`/`Tests` workflows.

### Tests

**Molecule** — one scenario per role, `ansible/molecule/<role>/` (scenario name = role name), run from `ansible/` (`molecule test -s <role>`).
- Shared base config: `.config/molecule/config.yml` at the repo root (auto-loaded): docker driver, image `homelab-molecule:debian13` built from `ansible/molecule/_shared/Dockerfile` (Debian 13, systemd PID 1, Docker daemon, user `sylvain` with sudo — the playbooks' connection model), connection as `sylvain` with `XDG_RUNTIME_DIR` so `scope: user` tasks work.
- Shared prepare `ansible/molecule/_shared/prepare.yml`: linger, Docker + `newt` network, a `dc@.service` drop-in that runs `docker compose config --quiet` then sleeps (no image is ever pulled), a `/root/.local/bin/borgmatic` stub that validates each config with the real borgmatic baked into the image (version pinned in the Dockerfile, Renovate-tracked) and fakes `repo-create` exactly like borgmatic 2.x (exit 0, "Repository already exists. Skipping creation." on stdout at `--verbosity 1`). A scenario needing more imports it from its own `prepare.yml`.
- `converge.yml` loads `_shared/vars/fake_secrets.yml` (a dummy for every key of `secrets.sops.yaml` that a role reads — add new keys there; `password`, read only by `00-setup.yaml`, is deliberately absent), `group_vars/all` and the **real** `host_vars/<host>` of the host running the role, then reproduces the playbook (roles before it, role-entry `vars:`, healthcheck `set_fact`s).
- `verify.yml` uses `_shared/tasks/verify_app.yml` for `dc@` apps plus role-specific assertions. Idempotence must hold.
- Never hardcode secret-looking literals in scenarios (GitGuardian fails the PR): compare against the fake-secret variables. Prefer 0700/0600 for files a prepare creates (SonarCloud).
- A new role gets a scenario: copy `ansible/molecule/trek/`. CI discovers it automatically.

**OpenTofu** — `tofu/<module>/tests/*.tftest.hcl`, run with `tofu init -backend=false && tofu test`: every provider is `mock_provider`, `sops_file` / `terraform_remote_state` / `http` data sources are `override_data`. Mostly `command = plan`; `apply` only where no `prevent_destroy` or provisioner exists. Some assertions read other repo files with `file()` (ansible inventory scripts, host_vars, playbooks) on purpose, to pin the Tofu ↔ Ansible contract. A module whose tests cannot run gets a `tests/.disabled` file stating why: CI discovery and `mise run tofu-test` skip it (CI prints the reason as a warning). That is the case of `keycloak_demo_planning_kc`, whose `realm` module points at a planning-equipes commit reachable from no branch or tag, and of `1y` and `site`, whose `import` blocks make `tofu test` panic (OpenTofu refuses imports in a test context, mocked or not): their suites pass on a copy without the block and come back once the block, only needed for the first apply, is removed. An `import` block is therefore incompatible with `tofu test` — prefer the `tofu import` CLI command documented in the module's README, as `tofu/1y` already does for its DNS record. CI uses the OpenTofu version pinned in `mise.toml`.

### Running a specific Ansible playbook

`mise run ansible-run` / `ansible-check` invoke a `site.yml` that does not exist in this repo — don't rely on them as-is. Instead, from `ansible/`, target the playbook for the host group you're changing:

```bash
ansible-playbook -i inventory/hosts 00-setup.yaml   # base host setup (user, packages, starship)
ansible-playbook -i inventory/hosts docker.yml       # Proxmox docker host: all the app roles
ansible-playbook -i inventory/hosts flip.yml         # Hetzner flip server: Flip Planning (prod + demo)
ansible-playbook -i inventory/hosts pangolin.yaml    # Pangolin Hetzner VM
ansible-playbook -i inventory/hosts pi.yml           # Raspberry Pi (Immich)
ansible-playbook -i inventory/hosts backup.yaml      # creates remote backup folders on the Storage Box
ansible-playbook -i inventory/hosts test.yaml
```

Add `--check` for a dry run, `--tags <tag>` to scope to one role/app (e.g. `--tags betisier`), and `-v`/`-vv`/`-vvv` for verbosity. `ansible.cfg` sets `stdout_callback = debug` and logs every run to `ansible/run.log`; fact cache lives in `ansible/facts/`.

**Inventory** is dynamic: `ansible/inventory/proxmox.py` and `ansible/inventory/hetzner.py` read the corresponding `tofu state -json` output (via `tofu show -json` run against `../tofu/proxmox` or `../tofu/pangolin`) to build host lists — so `tofu apply` must be current before an inventory-dependent Ansible run picks up new hosts. `ansible/inventory/hosts` is a static fallback (currently just the Raspberry Pi). A Hetzner server with no public IPv4 (flip) is emitted by `hetzner.py` with its private IP and `-o ProxyJump=sylvain@<pangolin public IP>` (Pangolin's sshd allows it via `security_ssh_allow_tcp_forwarding: local` in `host_vars/pangolin`); CI does the same (private IP + `ProxyJump=pangolin.sylvain.cloud`, bastion key in the runner's `~/.ssh/config`). Never point Ansible at `flip.internal`: that Pangolin private resource is served by flip's own Newt, so a play restarting newt or docker there cuts its own connection; it is only for manual access through a Pangolin client.

### Secrets (SOPS + Age)

- `secrets.sops.yaml` (repo root, and a copy loaded from `ansible/secrets.sops.yaml`) holds all secrets, encrypted with Age (`.sops.yaml` lists the recipient age public keys — perso/pro/semaphore).
- Age private key path is configured in `.sopsrc` (`ageKeyFile: /home/sylvain/.age.key`) — needed to decrypt.
- `mise.toml` auto-loads (and redacts) `secrets.sops.yaml` into task environments via `_.file`.
- In Ansible playbooks, secrets are loaded with:
  ```yaml
  community.sops.load_vars:
    file: "{{ playbook_dir }}/secrets.sops.yaml"
    expressions: evaluate-on-load
  ```
  **Warning carried over from the codebase itself**: variables loaded this way cannot override a variable that's already defined elsewhere — make sure the variable isn't already set before relying on the loaded value.

## Ansible architecture

### Host groups / playbook mapping

| Playbook | Host group | Purpose |
|---|---|---|
| `00-setup.yaml` | `all,!backups` | base setup: apt packages, timezone, `sylvain` user + SSH keys from `keys/*.pub`, starship prompt |
| `docker.yml` | `docker` | Proxmox Docker VM — installs Docker, `docker_service`, `borgmatic`, `newt`, then every app role |
| `pangolin.yaml` | `pangolin` | Hetzner Pangolin VM — Docker, `borgmatic`, `security` hardening, `pangolin` role |
| `pi.yml` | `pi` | Raspberry Pi — Docker, `docker_service`, `borgmatic`, `newt`, `immich` |
| `flip.yml` | `flip` | Hetzner flip server (no public IP) — `nat_client` first, then Docker, `docker_service`, `host_tuning`, `security`, `borgmatic`, `newt`, `flip_planning` ×2 (prod + demo). Newt credentials come from the `pangolin_config` state (`flip_newt_id`/`flip_newt_secret` outputs), not from SOPS |
| `backup.yaml` | `backups` | Storage Box only: `mkdir -p` remote backup folders (see below) |

`docker.yml`, `flip.yml` and `pangolin.yaml`/`pi.yml` all read the OpenTofu state for `pangolin_config` from the S3-compatible backend (`homelab-tf-state-sylvain` bucket at `s3.eu-west-par.io.cloud.ovh.net`) to pull Uptime Kuma healthcheck-push URLs as Terraform outputs, then pass them into the relevant roles. The SOPS load and the state read are shared: each playbook's first `pre_tasks` entry imports `ansible/tasks/pangolin_config_outputs.yml`, which sets the `terraform_outputs` fact (`no_log`); the playbook then `set_fact`s its own `<var>: "{{ terraform_outputs.<output>.value | default('') }}"` — keep that literal form in the playbook, `tofu/pangolin_config/tests/invariants.tftest.hcl` greps the playbooks for it.

### The `docker_service` role (systemd pattern)

Every containerized app runs as a **systemd user service** via a shared template instantiated per-service:

- `docker_service` role installs a `dc@.service` systemd *user* unit template (`roles/docker_service/templates/dc@.service.j2`) to `~/.config/systemd/user/dc@.service`, and enables lingering for the user (so services survive logout).
- Each app's compose project lives at `{{ docker_base_path }}/<service>` (default `docker_base_path: /opt/apps`), and is started as `dc@<service>.service` (`WorkingDirectory={{ docker_base_path }}/%i`). The unit waits (bounded) for the Docker daemon, pulls only the images that are missing (`ExecStartPre=docker compose pull --policy missing`, so a failed download fails the start job and the Ansible restart handler), then runs `docker compose up --remove-orphans` with no `--pull`: each service's `pull_policy` (default `missing`) decides, so a registry outage at boot cannot stop an app whose image is already present (images are digest-pinned, Renovate bumps them). It restarts every 15 s without a permanent give-up (`StartLimitIntervalSec=0`) and without a `RestartSteps` back-off, whose counter only resets on a manual start or `reset-failed`. An instance that must follow a mutable tag sets `pull_policy: always` on that service (e.g. `flip_planning_image_pull_policy` for the Keycloak bench).
- App roles just template a `compose.yaml` into that directory and `systemd: name=dc@<service> scope=user state=started enabled=true`, notifying a `Restart <service>` handler on change.

### Adding a new app role

Use the **`new-app`** project skill (`.claude/skills/new-app/`) for the full,
current checklist — it also delegates to **`pangolin-route`** and
**`borgmatic-backup`** for their respective pieces, and there's a
**`homelab-reviewer`** agent to sanity-check the resulting diff before
`tofu apply`/`ansible-playbook`. Summary:

- Role skeleton: `defaults/`, `handlers/`, `tasks/`, `templates/` under `ansible/roles/<service>/`. `ansible/roles/gramps` and `ansible/roles/trek` are the most current reference implementations.
- Compose file is always named `compose.yaml` (not `docker-compose.yml`).
- **Public HTTP routing is entirely OpenTofu-managed, not Docker labels.** Each exposed app gets a `tofu/pangolin_config/website_<service>.tf` declaring its entry of `local.websites` (name, domain, role, target(s), backup flag) and its outputs; `websites.tf` turns every entry into the `pangolin_resource` + `pangolin_target` (+ SSO role binding + healthcheck access token + Uptime Kuma monitors) with `for_each`, so the pins, the maintenance page and the probe settings are written once — Newt only reads the Docker socket to confirm the container is on its network, it doesn't parse any `pangolin.public-resources.*` labels (an earlier pattern, no longer used anywhere in this repo). The container must join the external `newt` Docker network (created by the `newt` role) for Pangolin to reach it. If the app has its own DB, put the DB on a second, internal, service-named network — never on `newt` — declared `internal: true` (no Internet route through it; the app keeps its own through `newt`) unless a container attached *only* to it needs the Internet: karakeep's crawler, immich's ML, dawarich's sidekiq, gramps' celery, meerkat_crm's backend (SMTP) stay non-internal; scanopy's too, not changed: its server talks to the host-network daemon through `host-gateway` and a published port, never tried on an internal network. Changing `internal` on an existing network: `docker compose up` recreates it only when it carries compose's config-hash label, and silently keeps a network created by an older compose as it was — run `docker compose down` once, then check `docker network inspect --format '{{.Internal}}' <network>`. A single-container app needs no private network at all. Two easy-to-miss details: every `pangolin_target` needs `hc_hostname` set explicitly (not inferred from `ip`; `websites.tf` sets it to `ip`, a hand-written target like NAS's or Proxmox's must set it), and multi-target path routing (`sub_targets`) needs the catch-all `"/"` at the *lowest* `priority` number, not the highest. Renaming an entry key or moving a resource into or out of the `for_each` needs a `moved` block, or its access token and push monitor are recreated.
- PUID/PGID come from `ansible_facts['user_uid']`/`user_gid'`, not hardcoded.
- `compose.yaml` (and `.env`) are templated `0600`: they carry secrets, and `dc@` reads them as their owner. `verify_app.yml` asserts it.
- Databases, redis/valkey and meilisearch get a `healthcheck` whose binary exists in the image (`pg_isready`; `healthcheck.sh --connect` for the official mariadb image; `mariadb-admin ping --host=127.0.0.1` for linuxserver's, which has no `healthcheck.sh`; `redis-cli`/`valkey-cli ping`, with `-a "$$REDIS_PASSWORD"` when a password is set), and whatever needs them waits with `depends_on: {<db>: {condition: service_healthy}}`. Databases also get `stop_grace_period: 60s`: `dc@` stops with `docker compose stop`, whose 10 s default SIGKILLs them. Molecule checks all three through `_shared/tasks/verify_compose_services.yml`.
- **Resource limits doctrine** (the Docker VM has 3 cores / 12 GiB on a rotational disk; aggregate CPU use is a few percent, so quotas only add latency):
  - Every service gets a `mem_limit` (hard cap). Size it at ~2× the measured peak (`memory.peak` in the container's cgroup), never below. A container pinned at its cap is not OOM-killed, it has its page cache evicted and thrashes the disk.
  - Databases (and anything measured at its cap) also get `mem_reservation` ≈ the peak: on cgroup v2 it becomes `memory.low` and protects their page cache.
  - **No `cpus:` on DBs, redis/valkey or interactive services.** A CFS quota below 1 core throttles any single-threaded burst even on an idle host.
  - Only batch-capable containers (OCR, document conversion, Celery/Sidekiq workers) get `cpus: 2.00` + `cpu_shares: 512`: the cap always leaves one core to the rest, the weight makes them lose under contention and costs nothing when idle.
  - Check images' default worker counts (`GUNICORN_NUM_WORKERS`, `pm.max_children`…) against the cap: gramps defaulted to 8 gunicorn workers of 170 MiB under a 1 GiB cap and OOM-looped.
- Backups use Borgmatic, not Restic. There is **one** config template for every app, `ansible/roles/borgmatic/templates/app.yaml.j2`, rendered by `ansible/roles/borgmatic/tasks/app.yml`: an app role calls it with `include_role: name=borgmatic tasks_from=app.yml` (+ `apply: tags: backup`) and `borgmatic_app_*` vars (name, sources, DB dumps, excludes, target, passphrase, healthcheck URL — documented in the role's `defaults/main.yml`); it never ships its own borgmatic template or repo-create task. Non-obvious structural rules the shared template keeps (deviating from these breaks Borgmatic):
  - Retention keys (`keep_daily`/`keep_weekly`/`keep_monthly`/`keep_yearly`) are **top-level**, not nested under `retention:`.
  - `checks:` (with `name`/`frequency`) is **top-level**, not nested under `consistency:`.
  - Use `commands:` with `before/after: action` + `when: [create]` hooks, not `before_backup`/`after_backup`/`on_error`.
  - `archive_name_format` is `'<service>-{now:%Y-%m-%dT%H:%M:%S}'` — no `{hostname}` prefix.
  - `compression: zstd,10`, not `auto,zstd`.
  - Target: `<service>_backup_borgmatic_target: "{{ backup_storage_box_url }}/<service>"` in the role defaults (`backup_storage_box_url` is a group var: `ssh://<user>@<host>/<path>`), passphrase `<service>_backup_encryption_passphrase: "{{ backup_passphrase }}"` there too — not in `host_vars`.
  - Never back up a live database directory: PostgreSQL/MySQL are dumped by the client inside the DB container (`borgmatic_app_postgresql_databases` / `_mysql_databases`), SQLite files copied by the host's `sqlite3 ".backup"` in a `before` hook into `/var/lib/borgmatic-sqlite/<app>/` (`borgmatic_app_sqlite_databases`, globs resolved at deploy time; their live copy is excluded). Never borgmatic's own `sqlite_databases`: its streamed `.dump` holds a read lock for the whole upload and froze Pangolin. MySQL/MariaDB dumps go through `/usr/local/bin/borgmatic-docker-dump`, since borgmatic 2.1 hands the client a host-side `--result-file`.
  - `exclude_patterns` are borg `fm:` patterns matched from the start of the archived path: `'*.log'` works anywhere, a relative `'cache/*'` matches nothing — app-specific excludes are absolute paths.
- New remote backup folders must be added to `backup_folders` in `ansible/host_vars/backups/variables.yaml` (created by `ansible/backup.yaml`, which must stay `gather_facts: false` + use `ansible.builtin.raw` because the Storage Box has a restricted shell — normal file modules don't work there).
- Register the new role's systemd unit as `dc@<service>` — don't template a bespoke `.service` file, `docker_service` already provides the generic template.
- Finally, add the role to the right playbook (`docker.yml` for the Proxmox host, `pangolin.yaml` for the Pangolin VM, etc.) with sensible tags (`<service>,app`), and wire its `<service>_backup_healthcheck_url` into that playbook's `pre_tasks` alongside the others.

### App data on the NAS

Apps can keep their data on the Ugreen NAS (NFSv4.1 export mounted on the
docker VM) while running on the VM; borg still backs everything up. Full
rationale and NAS-side setup: `nas-storage-docker/homelab-storage-architecture.md`.
Reference role: `ansible/roles/nginx_demo`. The rules:

- Declare `dependencies: [{role: nas_storage}]` in the app's `meta/main.yml`
  (not in `docker.yml`): it mounts `/mnt/nas/apps` (`hard`,
  `x-systemd.automount`) and runs once per play whatever the number of apps.
  `resolve_docker_tags.py` follows meta dependencies, so a `nas_storage`
  change redeploys its dependents.
- Data under `<service>_data_path: "{{ nas_storage_mount_path }}/<service>"`,
  created with `become: true` (the NFS rule is "No mapping" for the VM's IP),
  bind-mounted by absolute path. Never a Docker `driver_opts: nfs` volume:
  borg can't read it.
- Postgres/MariaDB data dirs may live there; **SQLite (and any mmap/lock-based
  embedded DB) never does** — it stays on the local disk.
- Every NAS-backed container gets `cgroup_parent: {{ nas_storage_slice }}`:
  that slice is ordered after the mount, so at VM shutdown the containers stop
  before the NAS is unmounted and the network goes down (a `hard` mount would
  otherwise hang Postgres' last checkpoint).
- A `dc@<service>.service.d/nas-storage.conf` user drop-in with
  `ExecStartPre={{ nas_storage_wait_command }} <timeout>`: at boot the VM is
  up before the NAS, and without the wait `dc@<service>` hits
  `StartLimitBurst` and stays failed. Keep the timeout under dc@'s
  `TimeoutStartSec` (300 s), pull included.
- Borgmatic: NAS file dirs in `source_directories`, the DB data dir **not**
  (dump via `postgresql_databases` + `pg_dump_command: docker exec …`),
  `source_directories_must_exist: true`, and a `before: configuration` hook
  running `{{ nas_storage_wait_command }} 30`: without it a dead NAS blocks
  the single `borgmatic.service`, hence every app's backup.
- DB passwords that Postgres only reads at initdb are drawn once and stored
  next to the cluster on the NAS (`nginx_demo_db_password_path`), not derived
  from `backup_passphrase`.
- Decommissioning: pass `<service>_data_path` in
  `decommission_app_extra_paths`, or the data stays orphaned on the NAS.
- Molecule: a container cannot mount the NFS export. Scenarios set
  `nas_storage_manage_mount: false` + `nas_storage_fstype: tmpfs` and reuse
  `ansible/molecule/nas_storage/prepare.yml`, which mounts a tmpfs (closed to
  "others") in its place: everything but the fstab/automount path is covered.
- No iSCSI: considered and rejected (see the doc).

### Running a second environment of an app

`flip_planning` is applied twice by `flip.yml`: once for production
(`flip-planning.sylvain.cloud`) and once for the demo
(`demo-planning.sylvain.dev`). There is one role, not two — duplicating a role
per environment is what leaves the copy behind on the next change.

What makes a role instantiable is that everything two instances cannot share on
one Docker host derives from two variables, set in `defaults/` and overridden as
**role parameters** in the playbook:

- `<service>_service` (snake_case) — the compose project **directory** under
  `docker_base_path`, the systemd unit (`dc@<service>`) and the borgmatic config
  filename. Those are the same string by construction: `dc@.service` runs in
  `/opt/apps/%i`. Compose derives its project name from that directory, so
  volumes and internal networks are namespaced for free.
- `<service>_container_prefix` (kebab-case) — every `container_name` and the
  private docker network, hence what the Pangolin targets resolve on `newt`.

Four non-obvious rules, each of which silently crosses the two environments if
broken:

- **`vars:` on the `roles:` entry, not `host_vars` — and never a `set_fact`
  of the same name.** `vars:` on a `roles:` entry wins over the role defaults,
  `host_vars` and the keys loaded from `secrets.sops.yaml`, but it **loses to
  a `set_fact`** (and to `include_vars`): checked, not assumed. An override
  placed in `host_vars` would apply to *both* instances; a play-level
  `set_fact` of a name the role reads silently beats every instance's
  override. That is how the demo's backups pushed to the production Uptime
  Kuma monitor until `flip.yml` stopped `set_fact`ing
  `flip_planning_backup_healthcheck_url` itself (it now sets
  `prod_planning_backup_healthcheck_url` and hands it to the production
  instance).
- **One handler per instance, notified through a variable.** Handler names are
  matched literally and handlers run once, at the end of the play: a single
  shared handler notified by both applications restarts whichever unit happened
  to be in scope. Tasks do `notify: "Restart {{ <service>_service }}"` and
  `handlers/main.yml` carries one static handler per environment.
- **`allow_duplicates: true` in `meta/main.yml`.** Ansible skips a repeat
  application of a role whose parameters are identical. Differing parameters
  make it run anyway, so this is belt and braces — but the belt is at the call
  site, and a future environment that overrode nothing would be skipped without
  a word.
- **`set_fact` outlives the role application.** Anything a role `set_fact`s
  leaks into the next instance in the same play. In `flip_planning` that is
  `flip_planning_trusted_proxies`, and it is deliberately fine (same host, same
  newt bridge, same subnet) — check that it is fine before adding another.

On the Tofu side nothing is shared: a second `website_<instance>.tf` whose
entry is listed in `local.websites` (`websites.tf`: its resource, access token
and Uptime Kuma monitors come from there, and `rules.tf`'s `managed_resources`
is derived from it), a second slug in `roles.tf`'s `apps` and, for a standalone
rule, an entry in `declared_extra_rules`. Secrets are per-environment too (`demo_planning_*` in
`secrets.sops.yaml`), so a leaked demo password cannot open the real planning.

### Removing an app role

Use the **`remove-app`** project skill (`.claude/skills/remove-app/`) for the
full checklist — it's the reverse of `new-app` and touches the same files.
Summary: run the reusable `ansible/roles/decommission_app` role (registered
in `docker.yml`/`pi.yml`/`flip.yml` under `tags: [decommission, never]`, so it only ever
runs when invoked explicitly via `--tags decommission`) to stop/disable the
`dc@<service>` unit and delete containers/volumes/data/borgmatic config, then
delete the role directory, deregister it from the playbook (role entry +
healthcheck `set_fact` line), remove its `host_vars`/`backup_folders`/secrets
entries, delete its `tofu/pangolin_config/website_<service>.tf`, its line in
`websites.tf`'s `local.websites` and its slug from `roles.tf`'s `apps` list
(then `tofu apply`), and finally grep the whole
repo for the service name to confirm nothing was missed. That last step
matters: the `photoprism` removal (commit `7e848ed`) skipped it and left
orphaned `host_vars`/`secrets.sops.yaml` entries behind for months.

### Config layering

- `ansible/group_vars/all/variables.yml` — shared defaults (`docker_base_path: /opt/apps`, `borgmatic_config_dir`, `newt_endpoint`, SSH user, etc.), plus vendored-role var files (`devsec.ssh_hardening.yml`, `geerlingguy.docker.yml`).
- `ansible/host_vars/<host>/` — per-host overrides (`docker`, `pangolin`, `pi`, `backups`). Note this is `host_vars/<hostname>`, matching the dynamic-inventory-generated host name, not a role/group name.
- Ansible collections live in `ansible/collections/ansible_collections/` and Galaxy roles in `ansible/galaxy_roles/`, both populated from `ansible/requirements.yml` (not committed as vendored source — reinstall via `ansible-galaxy install -r requirements.yml` if missing, or set up through mise/CI).

## OpenTofu architecture

- `tofu/proxmox/` — Proxmox VE provider: the Docker VM (`proxmox_docker_vm.tf`) and the Newt LXC container (`proxmox_newt_lxc.tf`) that `ansible/inventory/proxmox.py` reads back as inventory.
- `tofu/pangolin/` — Hetzner Cloud provider: the Pangolin VM, the flip VM (private network only) and the network route that makes Pangolin its NAT gateway, and Hetzner Storage Box config (see `STORAGE_BOX_SETUP.md` there for the manual setup steps SSH/rsync require). The state bucket is not here but in `tofu/s3_state/` (OVH Object Storage).
- `tofu/pangolin_config/` — Pangolin-side application config (roles, rules, private resources, per-app `website_*.tf` files declaring each public app as an entry of `local.websites`, from which `websites.tf` generates the resources, targets and Uptime Kuma checks) applied against the running Pangolin instance, separate from the VM provisioning itself. Its state is what `docker.yml`/`flip.yml`/`pangolin.yaml`/`pi.yml` read at Ansible time for healthcheck URLs (and, for `flip.yml`, the Newt credentials). It reads `tofu/pangolin`'s state (`remote_state.tf`) for flip's private IP, so `tofu/pangolin` is applied first. Every public resource is declared there — there is no hand-made public resource left (`SSH PI`, the last one, was deleted in favour of the private `pi.internal`), and the coverage precondition in `rules.tf` fails the plan on any enabled resource missing from `local.managed_resources` (derived from `local.websites`), so a resource created in the UI must be deleted or disabled there before the next apply. Optional+computed attributes of `pangolin_resource` (`mode`, `ssl`, `enabled`…) come from `local.resource_pins` (`resource_defaults.tf`); the only override is Gramps' `enabled = local.gramps_enabled`, false (app stopped, data kept), which also pauses its healthcheck monitor; its backup monitor stays active, the nightly backup still running. `headers` is in `ignore_changes` on all of them, deliberately (`websites.tf`): a `for_each` cannot vary its lifecycle and the provider cannot remove a header anyway, so a header set by hand in the UI no longer shows in a plan. The two VPN exit nodes, site resources `vpn` and `vpn-flip` in `gateway` mode, cannot be declared (provider 1.6.1 only knows `host`/`cidr`/`http`): they are made in the UI and audited by `terraform_data.vpn_gateways` (`private_resources.tf`), which fails the plan if one is missing, not in `gateway` mode, or, for `vpn-flip`, not on the `flip` site.
- `tofu/dns/` — OVH DNS zone records (`ovh_domain_zone_record` / `ovh_domain_zone_redirection`, not Cloudflare): the Pangolin A records (`*.sylvain.cloud`, the `sylvain.cloud` apex, `*.sylvain.dev`, and the `sylvain.dev` apex while `sylvain_dev_apex_to_pangolin` is true) read from `tofu/pangolin`'s state, the GitHub Pages challenges, the betisier redirect, and the `sylvain.dev` apex Google Search Console TXT record (`search_console.tf`). Cloudflare only appears in the Pages modules (`tofu/ref`, `tofu/site`, `tofu/1y`).
- `tofu/github/` — GitHub-side config: the Actions secrets of this repo (SOPS Age key, CI deploy key, OLM credentials read from `pangolin_config`'s state) and the `planning-equipes` repository itself — creation, visibility, `main` branch protection. The settings the provider can't reach (fork PR approval, private vulnerability reporting, GHCR package visibility, Renovate/GitGuardian) are a checklist in `tofu/github/README.md`.
- `tofu/ref/` — the referral site ref.sylvain.dev (repo `sylvainmetayer/ref`, 11ty on Cloudflare Pages): GitHub repository, Cloudflare Pages project + custom domain, Web Analytics site, and the OVH CNAME overriding the `*.sylvain.dev` wildcard. Needs `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID` in `secrets.sops.yaml`; see its README.
- `tofu/site/` — the personal site sylvain.dev (repo `sylvainmetayer/site`, 11ty on Cloudflare Pages, same pattern as `tofu/ref`, the pre-existing repository imported through an `import` block): the GitHub repository (secret scanning, Dependabot alerts without Dependabot PRs, a `main` ruleset requiring a PR and green checks, no bypass), its Actions secrets (Pages deploy hook for the daily build, SonarCloud token), Pages project `sylvain-dev` + custom domain `www.sylvain.dev` (webmention.io token as a production-only secret), the pre-existing Web Analytics site (imported), and the OVH CNAME for `www`. Pages only accepts an apex inside a Cloudflare zone, so the apex A record lives in `tofu/dns/pangolin.tf` (`sylvain_dev_root`, behind `sylvain_dev_apex_to_pangolin`) and Traefik answers it with a 301 to www through `pangolin_domain_redirects` (`ansible/host_vars/pangolin/variables.yaml`, routers in the pangolin role's dynamic config), which also serves a self-unregistering service worker in place of the old site's. Its README holds the Netlify cut-over order.
- `tofu/1y/` — the short-URL site r.sylvain.dev (repo `sylvainmetayer/1y`, 11ty on Cloudflare Pages, formerly Netlify): Cloudflare Pages project + custom domain, the OVH CNAME, and the GitHub repository itself (imported through an `import` block, settings aligned on `tofu/ref`, Dependabot PRs off in favour of Renovate). Same prerequisites as `tofu/ref`; the Pages build reads Node from `wrangler.toml`, and a precondition fails the plan when it drifts from the repo's `mise.toml`. See its README for the one-off DNS import of the Netlify-era record.
- All backends are S3-compatible object storage (`homelab-tf-state-sylvain` bucket at `https://s3.eu-west-par.io.cloud.ovh.net`), not native AWS — `backend "s3" { endpoints = { s3 = ... } }`.

## CI (GitHub Actions)

- `.github/workflows/lint.yaml` — `ansible-lint`, `tofu fmt -check` and `tofu validate` (pangolin, proxmox, pangolin_config, dns, github, ref, s3_state, site, 1y) on every PR.
- `.github/workflows/test.yaml` — discovers `ansible/molecule/*/molecule.yml` and `tofu/*/tests/` and runs one matrix job per Molecule scenario and per tested Tofu module (see "Tests" above).

- `.github/workflows/semaphore-image.yaml` — builds/pushes `compose/semaphore/Containerfile` to GHCR (`ghcr.io/sylvainmetayer/homelab/semaphore`) on changes to that file, tagging with the Semaphore version parsed out of the `FROM` line.
- `.github/workflows/ping.yaml` — manual (`workflow_dispatch`) connectivity test that starts an `fosrl/olm` (Pangolin's Outline-like mesh client) container on the runner, points the runner's system DNS at the OLM DNS proxy, and validates both public internet access and reachability of a private Pangolin resource (`docker-apps.internal:22`). Useful as a template if debugging OLM/Pangolin tunnel DNS issues — the key gotcha documented inline: `OVERRIDE_DNS=true` only rewrites `/etc/resolv.conf` *inside* the OLM container (different mount namespace), so the runner's own resolver must be repointed manually at `100.96.128.1`.

## Notes / gotchas

- SSH access to the Raspberry Pi is local-network only.
- Every public Pangolin resource only lets FR and DE through (`tofu/pangolin_config/rules.tf`; `apply_rules = true` on all of them, NAS and Proxmox included, pinned by the `every_public_resource_applies_its_rules` test, which also pins Betisier and nextcloud as the only resources without SSO), except the rules evaluated before the country rules. Priority 1 is a DROP of any path holding a backslash (`backslash_guard`) on every resource that has a path rule, since Pangolin does not normalise `\` and Node turns it into `/`. Priorities 2-9 hold the path ACCEPTs that answer from anywhere without SSO, protected by the app's own secret: share links, calendar feeds, client APIs, MCP/OAuth. Each app lists them next to its resource as `local.<app>_*_paths` (path => priority), aggregated in `local.path_bypasses`. Every path ACCEPT goes through `local.path_bypasses`, Karakeep's public lists, TREK's OAuth surface and the planning `/mcp/*` and KC `/auth/*` rules included (`pangolin_resource_rule.path_bypass["<Resource name> <path>"]`; a rule leaving a standalone resource for it needs a `moved` block, see `moved.tf`). Priorities 2-9 also hold the only standalone path rule, TREK's `/mcp` PASS (`trek_mcp`: skips the country rules, still requires SSO or a Pangolin access token; `local.standalone_path_rule_resources` keeps its backslash guard, and the `tied_rules_share_their_action` apply run fails if any PATH rule's resource has none), and the home-IP ACCEPTs at 9. Rules sharing a priority on one resource must share their action (`tied_rules_share_their_action` test). For a trip, add the country with an end date to `travel_countries` (`tofu/pangolin_config/variables.tf`) and apply: it gets its own priority (20), and the first apply after that date closes it again (the `travel_countries_stale` check then asks for the entry to be removed). Nothing applies `pangolin_config` on a schedule, so it stays open until someone does.
- The Pangolin `newt` container must share a Docker network with any app it fronts (socket-proxy access requirement).
- Cloud-init is cleaned in the Packer-built Pangolin image so it can be reconfigured on deploy.
