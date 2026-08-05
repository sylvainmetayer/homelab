# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A personal homelab infrastructure-as-code project (French comments/docs, English code). It provisions and configures two deployment targets:

1. **Pangolin** — a Hetzner Cloud VM running Pangolin Zero Trust (Traefik-based reverse proxy / tunnel), provisioned by `tofu/pangolin` and configured by `ansible/pangolin.yaml`.
2. **Proxmox** — a local Docker VM (+ a Newt LXC container) provisioned by `tofu/proxmox` and configured by `ansible/docker.yml`, running all the self-hosted apps (Nextcloud, Immich, Paperless-ngx, Monica, Wiki.js-style wiki, RSS reader, SearXNG, Semaphore, Betisier, Meerkat CRM, Flip Planning, SparkyFitness, Homelable, etc.).

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

# Misc
mise run generate_password "<plain>"   # mkpasswd sha512 for a host user password
mise run get_state                     # dumps `tofu state pull` for the current dir to state.json
```

There is no test/lint/build for `tofu/pangolin_config` wired into `mise.toml` — run `tofu fmt`/`validate`/`plan` manually from that directory when editing it.

### Running a specific Ansible playbook

`mise run ansible-run` / `ansible-check` invoke a `site.yml` that does not exist in this repo — don't rely on them as-is. Instead, from `ansible/`, target the playbook for the host group you're changing:

```bash
ansible-playbook -i inventory/hosts 00-setup.yaml   # base host setup (user, packages, starship)
ansible-playbook -i inventory/hosts docker.yml       # Proxmox docker host: all the app roles
ansible-playbook -i inventory/hosts pangolin.yaml    # Pangolin Hetzner VM
ansible-playbook -i inventory/hosts pi.yml           # Raspberry Pi (Immich)
ansible-playbook -i inventory/hosts backup.yaml      # creates remote backup folders on the Storage Box
ansible-playbook -i inventory/hosts test.yaml
```

Add `--check` for a dry run, `--tags <tag>` to scope to one role/app (e.g. `--tags betisier`), and `-v`/`-vv`/`-vvv` for verbosity. `ansible.cfg` sets `stdout_callback = debug` and logs every run to `ansible/run.log`; fact cache lives in `ansible/facts/`.

**Inventory** is dynamic: `ansible/inventory/proxmox.py` and `ansible/inventory/hetzner.py` read the corresponding `tofu state -json` output (via `tofu show -json` run against `../tofu/proxmox` or `../tofu/pangolin`) to build host lists — so `tofu apply` must be current before an inventory-dependent Ansible run picks up new hosts. `ansible/inventory/hosts` is a static fallback (currently just the Raspberry Pi).

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
| `backup.yaml` | `backups` | Storage Box only: `mkdir -p` remote backup folders (see below) |

`docker.yml` and `pangolin.yaml`/`pi.yml` all read the OpenTofu state for `pangolin_config` from the S3-compatible backend (`homelab-tf-state-sylvain` bucket at `s3.eu-west-par.io.cloud.ovh.net`) to pull Uptime Kuma healthcheck-push URLs as Terraform outputs, then pass them into the relevant roles.

### The `docker_service` role (systemd pattern)

Every containerized app runs as a **systemd user service** via a shared template instantiated per-service:

- `docker_service` role installs a `dc@.service` systemd *user* unit template (`roles/docker_service/templates/dc@.service.j2`) to `~/.config/systemd/user/dc@.service`, and enables lingering for the user (so services survive logout).
- Each app's compose project lives at `{{ docker_base_path }}/<service>` (default `docker_base_path: /opt/apps`), and is started as `dc@<service>.service` (`WorkingDirectory=/opt/apps/%i`, runs `docker compose pull && up`).
- App roles just template a `compose.yaml` into that directory and `systemd: name=dc@<service> scope=user state=started enabled=true`, notifying a `Restart <service>` handler on change.

### Adding a new app role

Use the **`new-app`** project skill (`.claude/skills/new-app/`) for the full,
current checklist — it also delegates to **`pangolin-route`** and
**`borgmatic-backup`** for their respective pieces, and there's a
**`homelab-reviewer`** agent to sanity-check the resulting diff before
`tofu apply`/`ansible-playbook`. Summary:

- Role skeleton: `defaults/`, `handlers/`, `tasks/`, `templates/` under `ansible/roles/<service>/`. `ansible/roles/sparky_fitness` and `ansible/roles/homelable` are the most current reference implementations.
- Compose file is always named `compose.yaml` (not `docker-compose.yml`).
- **Public HTTP routing is entirely OpenTofu-managed, not Docker labels.** Each exposed app gets a `tofu/pangolin_config/website_<service>.tf` defining a `pangolin_resource` + `pangolin_target` (+ SSO role binding + Uptime Kuma monitors) against the Pangolin provider — Newt only reads the Docker socket to confirm the container is on its network, it doesn't parse any `pangolin.public-resources.*` labels (an earlier pattern, no longer used anywhere in this repo). The container must join the external `newt` Docker network (created by the `newt` role) for Pangolin to reach it. If the app has its own DB, put the DB on a second, internal, service-named network — never on `newt`. Two easy-to-miss details: every `pangolin_target` needs `hc_hostname` set explicitly (not inferred from `ip`), and multi-target path routing needs the catch-all `"/"` at the *lowest* `priority` number, not the highest.
- PUID/PGID come from `ansible_facts['user_uid']`/`user_gid'`, not hardcoded.
- Backups use Borgmatic, not Restic. Reference template: `ansible/roles/betisier/templates/borgmatic-betisier.yaml.j2`. Non-obvious structural rules (deviating from these breaks Borgmatic):
  - Retention keys (`keep_daily`/`keep_weekly`/`keep_monthly`/`keep_yearly`) are **top-level**, not nested under `retention:`.
  - `checks:` (with `name`/`frequency`) is **top-level**, not nested under `consistency:`.
  - Use `commands:` with `before/after: action` + `when: [create]` hooks, not `before_backup`/`after_backup`/`on_error`.
  - `archive_name_format` is `'<service>-{now:%Y-%m-%dT%H:%M:%S}'` — no `{hostname}` prefix.
  - `compression: zstd,10`, not `auto,zstd`.
  - Target format: `ssh://{{ backup_storage_box_username }}@{{ backup_storage_box_hostname }}/{{ backup_storage_box_path }}/<service>`.
- New remote backup folders must be added to `backup_folders` in `ansible/host_vars/backups/variables.yaml` (created by `ansible/backup.yaml`, which must stay `gather_facts: false` + use `ansible.builtin.raw` because the Storage Box has a restricted shell — normal file modules don't work there).
- Register the new role's systemd unit as `dc@<service>` — don't template a bespoke `.service` file, `docker_service` already provides the generic template.
- Finally, add the role to the right playbook (`docker.yml` for the Proxmox host, `pangolin.yaml` for the Pangolin VM, etc.) with sensible tags (`<service>,app`), and wire its `<service>_backup_healthcheck_url` into that playbook's `pre_tasks` alongside the others.

### Removing an app role

Use the **`remove-app`** project skill (`.claude/skills/remove-app/`) for the
full checklist — it's the reverse of `new-app` and touches the same files.
Summary: run the reusable `ansible/roles/decommission_app` role (registered
in `docker.yml`/`pi.yml` under `tags: [decommission, never]`, so it only ever
runs when invoked explicitly via `--tags decommission`) to stop/disable the
`dc@<service>` unit and delete containers/volumes/data/borgmatic config, then
delete the role directory, deregister it from the playbook (role entry +
healthcheck `set_fact` line), remove its `host_vars`/`backup_folders`/secrets
entries, delete its `tofu/pangolin_config/website_<service>.tf` and its slug
from `roles.tf`'s `apps` list (then `tofu apply`), and finally grep the whole
repo for the service name to confirm nothing was missed. That last step
matters: the `photoprism` removal (commit `7e848ed`) skipped it and left
orphaned `host_vars`/`secrets.sops.yaml` entries that are still there today.

### Config layering

- `ansible/group_vars/all/variables.yml` — shared defaults (`docker_base_path: /opt/apps`, `borgmatic_config_dir`, `newt_endpoint`, SSH user, etc.), plus vendored-role var files (`devsec.ssh_hardening.yml`, `geerlingguy.docker.yml`).
- `ansible/host_vars/<host>/` — per-host overrides (`docker`, `pangolin`, `pi`, `backups`). Note this is `host_vars/<hostname>`, matching the dynamic-inventory-generated host name, not a role/group name.
- Ansible collections live in `ansible/collections/ansible_collections/` and Galaxy roles in `ansible/galaxy_roles/`, both populated from `ansible/requirements.yml` (not committed as vendored source — reinstall via `ansible-galaxy install -r requirements.yml` if missing, or set up through mise/CI).

## OpenTofu architecture

- `tofu/proxmox/` — Proxmox VE provider: the Docker VM (`proxmox_docker_vm.tf`) and the Newt LXC container (`proxmox_newt_lxc.tf`) that `ansible/inventory/proxmox.py` reads back as inventory.
- `tofu/pangolin/` — Hetzner Cloud provider: the Pangolin VM, an S3 bucket, and Hetzner Storage Box config (see `STORAGE_BOX_SETUP.md` there for the manual setup steps SSH/rsync require).
- `tofu/pangolin_config/` — Pangolin-side application config (roles, rules, private resources, per-app `website_*.tf` files defining public routing + Uptime Kuma checks) applied against the running Pangolin instance, separate from the VM provisioning itself. Its state is what `docker.yml`/`pangolin.yaml`/`pi.yml` read at Ansible time for healthcheck URLs.
- `tofu/dns/` — Cloudflare DNS records (root domain, redirects, GitHub Pages, email, Pangolin subdomain).
- All backends are S3-compatible object storage (`homelab-tf-state-sylvain` bucket at `https://s3.eu-west-par.io.cloud.ovh.net`), not native AWS — `backend "s3" { endpoints = { s3 = ... } }`.

## CI (GitHub Actions)

- `.github/workflows/semaphore-image.yaml` — builds/pushes `compose/semaphore/Containerfile` to GHCR (`ghcr.io/sylvainmetayer/homelab/semaphore`) on changes to that file, tagging with the Semaphore version parsed out of the `FROM` line.
- `.github/workflows/ping.yaml` — manual (`workflow_dispatch`) connectivity test that starts an `fosrl/olm` (Pangolin's Outline-like mesh client) container on the runner, points the runner's system DNS at the OLM DNS proxy, and validates both public internet access and reachability of a private Pangolin resource (`docker-apps.internal:22`). Useful as a template if debugging OLM/Pangolin tunnel DNS issues — the key gotcha documented inline: `OVERRIDE_DNS=true` only rewrites `/etc/resolv.conf` *inside* the OLM container (different mount namespace), so the runner's own resolver must be repointed manually at `100.96.128.1`.

## Notes / gotchas

- SSH access to the Raspberry Pi is local-network only.
- The Pangolin `newt` container must share a Docker network with any app it fronts (socket-proxy access requirement).
- Cloud-init is cleaned in the Packer-built Pangolin image so it can be reconfigured on deploy.
