# AGENTS.md

Guidance for coding agents (Claude Code loads this file in every session). It is an **index**: what the repo is, the commands, the rules whose breach causes an outage or a leak, and where every detail lives. Read the file the map points to before changing that area.

## What this repo is

A personal homelab infrastructure-as-code project (French comments/docs, English code). Deployment targets:

1. **Pangolin** — a Hetzner Cloud VM running Pangolin Zero Trust (Traefik-based reverse proxy / tunnel), provisioned by `tofu/pangolin` and configured by `ansible/pangolin.yaml`.
2. **Proxmox** — a local Docker VM provisioned by `tofu/proxmox` and configured by `ansible/docker.yml`, running the self-hosted apps (`docs/apps.md` lists every app, its role and its host), plus a Newt LXC container (`proxmox_newt_lxc.tf`, configured by `ansible/lxc.yml`) that serves the `proxmox-lxc` site: the LAN private resources, through which the CI reaches the home hosts.
3. **Flip** — a Hetzner Cloud VM with **no public IP** (private network only), provisioned by `tofu/pangolin/flip.tf` and configured by `ansible/flip.yml`, dedicated to Flip Planning (production + demo), plus Promptoramix (the stateless Linkx tournament AI bot). Pangolin reaches it through the Newt running on it (site `flip`); it reaches the Internet through Pangolin, which NATs for the private network (`hcloud_network_route` in `tofu/pangolin/nat.tf`, roles `nat_gateway` on Pangolin and `nat_client` on flip).

Also: a Raspberry Pi (`ansible/pi.yml`, Immich, Blocky), the Ugreen NAS (`ansible/nas.yml`, Jellyfin), the Proxmox host itself (`ansible/pve.yml`), and a Hetzner Storage Box used purely as an Ansible group (`backups`) for remote backup folder provisioning.

Stack: **OpenTofu** (infra) → **Ansible** (host config + app deploy via Docker Compose) → **SOPS/Age** (secrets) → **Borgmatic** (backups to Hetzner Storage Box).

Pour les humains : la carte du homelab est dans `docs/architecture.md`, les procédures d'incident dans `docs/runbooks/`, les décisions d'architecture (ADR, une par fichier, index et modèle dans `docs/adr/README.md`) dans `docs/adr/` : une nouvelle décision structurante y ajoute un fichier.

## Commands

All commands run through **mise** (not make). Tool versions are pinned in `mise.toml`; run `mise install` once, then `uv sync` for the Python venv.

```bash
mise run init           # tofu/pangolin; then plan, apply
mise run init-proxmox   # tofu/proxmox; then plan-proxmox, apply-proxmox
mise run init-ref       # tofu/ref (GITHUB_TOKEN exporté avant); then plan-ref, apply-ref
mise run lint        # tofu fmt -check -recursive + init -backend=false && validate of every module
mise run fix-lint    # tofu fmt -recursive
mise run ansible-lint
mise run lint-ci     # zizmor, actionlint, hadolint
mise run molecule [role]   # Molecule scenario of one role (all when omitted); builds the test image first
mise run tofu-test         # tofu test of every tofu/<module> that has a tests/ dir
mise run generate_password # prints the sha512 hash to store as host_user_password_hash
mise run secrets-scan      # gitleaks over the whole history
mise run test-cle-secours <keyfile>  # quarterly secours age key test, sets dernier_test (docs/runbooks/test-cle-secours.md)
```

`mise run lint` validates the same modules as the `OpenTofu lint` job (pangolin, proxmox, pangolin_config, dns, github, ref, s3_state, keepass_backup, site, 1y, keycloak_demo_planning_kc), without touching any state. Modules with no plan task (`pangolin_config`, `dns`, `github`…): `mise exec -- tofu -chdir=tofu/<module> plan`. CI script tests: `python -I -m unittest discover -s .github/scripts -p 'test_*.py'`.

There is no mise task running a playbook and no `site.yml`: from `ansible/`, run the playbook of the host group you change (`00-setup.yaml`, `docker.yml`, `flip.yml`, `pangolin.yaml`, `pi.yml`, `lxc.yml`, `nas.yml`, `pve.yml`, `backup.yaml`, `pc-nas.yml`), with `--check`, `--tags <role>`, `-v`. **No `-i`**: `ansible.cfg` sets `inventory = ./inventory` (`proxmox.py`, `hetzner.py` and `hosts` together); `-i inventory/hosts` alone would only know the static hosts (Pi, LXC, NAS, Proxmox host). Every run is logged to `ansible/run.log`. Detail (inventory, flip's bastion jump, the host table): `docs/conventions/ansible.md`.

## Hard rules (one line each; the pointer has the detail)

- **Never commit on `main`, nor in the main checkout**: one git worktree per branch, a PR per change. Sylvain runs the applies and deploys himself unless he delegates them in the session.
- **Merge to `main` deploys**: a push touching `ansible/roles/**`, a host playbook, `ansible/host_vars/<host>/`, `ansible/group_vars/all/**`, `ansible/tasks/**` or `ansible/requirements.yml` runs `deploy-docker-app` against the real hosts, with the tags `resolve_docker_tags.py` derives (a role's `README.md` deploys nothing; a playbook's changed role entries deploy their tags, any other playbook change or a host_vars change the whole playbook, a shared file all four playbooks whole; a bump of the `secrets/` submodule deploys nothing). `nas.yml`, `pve.yml` and `lxc.yml` are never run by CI: by hand only. → `docs/conventions/ci.md`
- **SOPS precedence**: keys of `secrets/ansible.sops.yaml` land in the `include_vars` layer and beat role defaults, host_vars, play and role-entry `vars:`; so a SOPS key never bears the name of a variable a playbook or role sets (prefix per instance, hand it over in the role entry's `vars:`). `check_sops_shadowing.py` fails on it. → `docs/conventions/secrets.md`
- **Facts are read as `ansible_facts[...]`**: `inject_facts_as_vars = False` (`ansible.cfg`, and Molecule), so a bare `ansible_<fact>` is undefined. → `docs/conventions/secrets.md`
- **Secrets live in the `secrets/` submodule** (private `homelab-secrets`, ADR 0018): `git submodule update --init` in every clone and worktree; a secret change is a commit pushed there, then the submodule bump here in a PR; never bring a SOPS file or the inventory back into this public repo. → `docs/conventions/secrets.md`
- **Every SOPS key has a `secrets/secrets-rotation.yaml` entry** (added/removed with the key; `last_rotated` + `estimated: false` after a rotation). → `docs/conventions/secrets.md`, `docs/runbooks/rotation-des-secrets.md`
- **Secrets in Ansible**: `compose.yaml`/`.env` templated `0600` with `diff: false`; every `set_fact` of a push URL or token `no_log: true` (else `--diff`/`-v` write them to `run.log` and the CI logs). Never a secret-looking literal in Molecule (GitGuardian). → new-app skill
- **Pangolin provider: declare every optional+computed attribute.** Undeclared, the plan says « No changes » whatever the live value (two outages: flip-planning's targets destroyed, targets stored with no probe scheme → 503). `pangolin_resource` takes them from `local.resource_pins` (`resource_defaults.tf`), targets get their `hc_*` from `websites.tf`. Not needed on Uptime Kuma monitors: `breml/uptimekuma` 0.4.0 gives each a fixed default it re-reads from the API, so a UI change shows in the plan (re-check on a provider upgrade). → `tofu/pangolin_config/README.md`
- **`pangolin_site_resource` in-place update wipes its role/user/client bindings** (provider 1.6.1): every binding carries `replace_triggered_by`; always re-plan after an apply that touched a private resource — it must be empty. → `tofu/pangolin_config/README.md`
- **Public Pangolin resources let FR and DE only** (`rules.tf`); every path ACCEPT (no SSO, from anywhere) goes through `local.path_bypasses`, read off the image version in `path_bypass_images.json`. → `tofu/pangolin_config/README.md`
- **Never point Ansible at `flip.internal`** (served by flip's own Newt: a play restarting newt or docker cuts its own connection). → `docs/conventions/ansible.md`
- **`ansible/known_hosts` is strict** (`StrictHostKeyChecking=yes`, bastion jump included): a rebuilt host's key is read on the host, never `ssh-keyscan`. → `tofu/pangolin/README.md`, `docs/runbooks/cle-hote-ssh-changee.md`
- **Resource limits doctrine** (Docker VM: 3 cores / 12 GiB on an entry-level SATA SSD): `mem_limit` ≈ 2× measured peak on every service, `mem_reservation` on DBs, no `cpus:` except `cpus: 2.00` + `cpu_shares: 512` on batch workers. → `docs/conventions/resource-limits.md`
- **No `import` block in a tested module**: it makes `tofu test` panic; use the `tofu import` CLI documented in the module's README. → `docs/conventions/tests.md`
- **Renovate automerge is an allowlist of stateless images** (and action patches); never add a DB image, `flip_planning`, or an image of `path_bypass_images.json`. A merged image that crashes: revert **and** drop it from the allowlist. → `docs/conventions/ci.md`
- **Pausing an app moves four switches together** (`<service>_enabled: false`, `enabled = false` in `local.websites`, the paused list in `pangolin_config`'s invariants, `"paused": true` in `apps.json`) plus Renovate's « Paused apps » rules. → `docs/runbooks/app-en-pause.md`, `docs/conventions/app-lifecycle.md`
- **Backups are Borgmatic through the one shared template** (`borgmatic` role, `tasks_from: app.yml`), never a live DB directory, never borgmatic's `sqlite_databases`. → `ansible/roles/borgmatic/README.md`, `borgmatic-backup` skill
- **Public HTTP routing is Tofu-managed** (`website_<service>.tf` entry of `local.websites`), never Docker labels; the app joins the external `newt` network, its DB never does. → `pangolin-route` skill
- **A role applied more than once** (`flip_planning`): overrides as role-entry `vars:`, never `host_vars`, a `set_fact` or a SOPS key of the same name. → `docs/conventions/app-lifecycle.md`

## Skills and agent

- `new-app` (`.claude/skills/new-app/`): add an app; holds the former « Adding a new app role » section. Delegates to `pangolin-route` (Pangolin resource, targets, SSO, monitors) and `borgmatic-backup`.
- `remove-app`: decommission an app (`decommission_app` role, `--tags decommission`), then grep the repo for the name.
- `homelab-reviewer` agent: review a diff before `tofu apply` / `ansible-playbook`.

## Current state worth knowing

- Papra (role `papra`, `papra.sylvain.cloud`) is on trial as Paperless-ngx's replacement (Paperless is paused): whichever loses is removed with `remove-app`. Its OCR fetches models from `cdn.jsdelivr.net` per document. → `ansible/roles/papra/README.md`
- `tofu/1y`: its `import` block was removed on 2026-10-29, its tests are back.

## Map: topic → file to read

| Topic | File |
|---|---|
| Apps, their role and host | `docs/apps.md` |
| Human map of the homelab (FR) | `docs/architecture.md` |
| Incident procedures (FR) | `docs/runbooks/README.md` |
| Architecture decisions | `docs/adr/README.md` |
| Playbooks per host group, inventory, flip bastion, `pangolin_config` state read, config layering | `docs/conventions/ansible.md` |
| Secrets: SOPS files, age recipients, `load_vars`, precedence, rotation inventory | `docs/conventions/secrets.md` |
| Molecule and `tofu test` conventions | `docs/conventions/tests.md` |
| CI workflows, deploy logic, Renovate automerge, restore test, scheduled checks | `docs/conventions/ci.md` |
| Resource limits doctrine | `docs/conventions/resource-limits.md` |
| Second environment of an app, pausing, removing | `docs/conventions/app-lifecycle.md` |
| OpenTofu backends, state encryption | `docs/conventions/opentofu.md` |
| `dc@.service` systemd pattern, NAS system scope, weekly unused-image prune | `ansible/roles/docker_service/README.md` |
| App data on the NAS (NFS) | `ansible/roles/nas_storage/README.md` |
| Borgmatic template rules, NAS container mode, Storage Box subaccounts | `ansible/roles/borgmatic/README.md` |
| Host hardening (ufw, fail2ban, devsec, ssh-audit), LAN hosts' SSH | `ansible/roles/security/README.md` |
| Newt and its socket proxy | `ansible/roles/newt/README.md` |
| Uptime Kuma pushes from scripts and units (`uptime-push`, options, worst case) | `ansible/roles/uptime_push/README.md` |
| Homepage widgets | `ansible/roles/homepage/README.md` |
| Monitoring (Beszel hub + agents) | `ansible/roles/beszel/README.md` |
| Logs (VictoriaLogs + Vector) | `ansible/roles/victoria_logs/README.md` |
| Weekly memory report | `ansible/roles/mem_report/README.md` |
| ntfy: topics, grants, removing one, « no subscriber » alert | `ansible/roles/ntfy/README.md` |
| CrowdSec, GeoLite2 on Pangolin | `ansible/roles/pangolin/README.md` |
| Flip Planning instances | `ansible/roles/flip_planning/README.md` |
| NAS: TLS proxy, Jellyfin network, kDrive mirror | `ansible/roles/nas_proxy/README.md`, `ansible/roles/jellyfin/README.md`, `ansible/roles/kdrive_sync/README.md` |
| Proxmox host: vzdump restore test; pending apt updates notices (pve, docker, pi, flip, pangolin) | `ansible/roles/vzdump_restore_test/README.md`, `ansible/roles/update_notify/README.md` |
| Papra trial | `ansible/roles/papra/README.md` |
| Proxmox VM, LXC, vzdump job | `tofu/proxmox/README.md` |
| Hetzner VMs, NAT, Storage Box; Pangolin server rebuild | `tofu/pangolin/README.md` (+ `STORAGE_BOX_SETUP.md`) |
| Pangolin config: resources, rules, path bypasses, private resources, bindings | `tofu/pangolin_config/README.md` |
| DNS, mail authentication, CAA | `tofu/dns/README.md`, `docs/runbooks/dmarc.md` |
| GitHub repos, rulesets, Actions environments | `tofu/github/README.md` |
| Pages sites | `tofu/site/README.md`, `tofu/ref/README.md`, `tofu/1y/README.md` |
| KeePass restic bucket | `tofu/keepass_backup/README.md` |
| Restore test | `.github/restore-test/README.md` |
