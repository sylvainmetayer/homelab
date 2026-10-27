# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A personal homelab infrastructure-as-code project (French comments/docs, English code). It provisions and configures two deployment targets:

1. **Pangolin** — a Hetzner Cloud VM running Pangolin Zero Trust (Traefik-based reverse proxy / tunnel), provisioned by `tofu/pangolin` and configured by `ansible/pangolin.yaml`.
2. **Proxmox** — a local Docker VM provisioned by `tofu/proxmox` and configured by `ansible/docker.yml`, running the self-hosted apps (`docs/apps.md` lists every app, its role and its host), plus a Newt LXC container (`proxmox_newt_lxc.tf`, configured by `ansible/lxc.yml`) that serves the `proxmox-lxc` site: the LAN private resources, through which the CI reaches the home hosts.
3. **Flip** — a Hetzner Cloud VM with **no public IP** (private network only), provisioned by `tofu/pangolin/flip.tf` and configured by `ansible/flip.yml`, dedicated to Flip Planning (production + demo), plus Promptoramix (the stateless Linkx tournament AI bot). Pangolin reaches it through the Newt running on it (site `flip`); it reaches the Internet through Pangolin, which NATs for the private network (`hcloud_network_route` in `tofu/pangolin/nat.tf`, roles `nat_gateway` on Pangolin and `nat_client` on flip).

There's also a Raspberry Pi (`ansible/pi.yml`, Immich) and a Hetzner Storage Box used purely as an Ansible group (`backups`) for remote backup folder provisioning.

Stack: **OpenTofu** (infra) → **Ansible** (host config + app deploy via Docker Compose) → **SOPS/Age** (secrets) → **Borgmatic** (backups to Hetzner Storage Box).

Pour les humains : la carte du homelab est dans `docs/architecture.md`, les procédures d'incident dans `docs/runbooks/`.

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

# OpenTofu linting (every module the Lint workflow checks)
mise run lint             # tofu fmt -check -recursive + init -backend=false && validate of every module
mise run fix-lint          # tofu fmt -recursive

# Ansible (run from ansible/, or via mise which cd's there)
mise run ansible-lint

# Tests (see "Tests" below)
mise run molecule [role]   # Molecule scenario of one role (all when omitted); builds the test image first
mise run tofu-test         # tofu test of every tofu/<module> that has a tests/ dir

# Misc
mise run generate_password            # prompts, prints the sha512 hash to store as host_user_password_hash
```

`mise run lint` validates the same modules as the `OpenTofu lint` job (pangolin, proxmox, pangolin_config, dns, github, ref, s3_state, site, 1y), without touching any state. There is no mise task running a playbook: see below.

### Tests

**Molecule** — one scenario per role, `ansible/molecule/<role>/` (scenario name = role name), run from `ansible/` (`molecule test -s <role>`). Exception: `security_flip` replays the `security` role with flip's host_vars (no SSH forwarding, private network never banned), sharing `security`'s prepare and verify tasks.
- Shared base config: `.config/molecule/config.yml` at the repo root (auto-loaded): docker driver, image `homelab-molecule:debian13` built from `ansible/molecule/_shared/Dockerfile` (Debian 13, systemd PID 1, Docker daemon, user `sylvain` with sudo — the playbooks' connection model), connection as `sylvain` with `XDG_RUNTIME_DIR` so `scope: user` tasks work.
- Shared prepare `ansible/molecule/_shared/prepare.yml`: linger, Docker + `newt` network, a `dc@.service` drop-in that runs `docker compose config --quiet` then sleeps (no image is ever pulled), a `/root/.local/bin/borgmatic` stub that validates each config with the real borgmatic baked into the image (version pinned in the Dockerfile, Renovate-tracked) and fakes `repo-create` exactly like borgmatic 2.x (exit 0, "Repository already exists. Skipping creation." on stdout at `--verbosity 1`). A scenario needing more imports it from its own `prepare.yml`.
- `converge.yml` loads `_shared/vars/fake_secrets.yml` through `_shared/tasks/load_fake_secrets.yml`, its first pre_task (`include_vars`: the same precedence layer as `community.sops.load_vars`, which a `vars_files` entry would not reproduce) (a dummy for every key of `secrets.sops.yaml` that a role reads — add new keys there; `host_user_password_hash`, read only by `00-setup.yaml`, is deliberately absent), `group_vars/all` and the **real** `host_vars/<host>` of the host running the role, then reproduces the playbook (roles before it, role-entry `vars:`, healthcheck `set_fact`s).
- `verify.yml` uses `_shared/tasks/verify_app.yml` for `dc@` apps plus role-specific assertions. Idempotence must hold.
- Never hardcode secret-looking literals in scenarios (GitGuardian fails the PR): compare against the fake-secret variables. Prefer 0700/0600 for files a prepare creates (SonarCloud).
- A new role gets a scenario: copy `ansible/molecule/trek/`. CI discovers it automatically.

**OpenTofu** — `tofu/<module>/tests/*.tftest.hcl`, run with `tofu init -backend=false && tofu test`: every provider is `mock_provider`, `sops_file` / `terraform_remote_state` / `http` data sources are `override_data`. Mostly `command = plan`; `apply` only where no `prevent_destroy` or provisioner exists. Some assertions read other repo files with `file()` (ansible inventory scripts, host_vars, playbooks) on purpose, to pin the Tofu ↔ Ansible contract. A module whose tests cannot run gets a `tests/.disabled` file stating why: CI discovery and `mise run tofu-test` skip it (CI prints the reason as a warning). That is the case of `keycloak_demo_planning_kc`, whose `realm` module points at a planning-equipes commit reachable from no branch or tag, and of `1y`, whose `import` block makes `tofu test` panic (OpenTofu refuses imports in a test context, mocked or not): its suite passes on a copy without the block and comes back once the block, only needed for the first apply, is removed (as `tofu/site` did on 2026-10-27). An `import` block is therefore incompatible with `tofu test` — prefer the `tofu import` CLI command documented in the module's README, as `tofu/1y` already does for its DNS record. CI uses the OpenTofu version pinned in `mise.toml`.

### Running a specific Ansible playbook

There is no `site.yml`: from `ansible/`, target the playbook for the host group you're changing:

```bash
ansible-playbook 00-setup.yaml   # base host setup (user, packages, starship)
ansible-playbook docker.yml      # Proxmox docker host: all the app roles
ansible-playbook flip.yml        # Hetzner flip server: Flip Planning (prod, demo, Keycloak demo), Promptoramix
ansible-playbook pangolin.yaml   # Pangolin Hetzner VM
ansible-playbook pi.yml          # Raspberry Pi (Immich)
ansible-playbook lxc.yml         # Proxmox Newt LXC (site proxmox-lxc)
ansible-playbook backup.yaml     # authorizes each host's borgmatic key on its Storage Box subaccount
ansible-playbook test.yaml
```

No `-i`: `ansible.cfg` sets `inventory = ./inventory`, i.e. `proxmox.py`, `hetzner.py` and `hosts` together. `-i inventory/hosts` alone would only know the Pi and the LXC.

Add `--check` for a dry run, `--tags <tag>` to scope to one role/app (e.g. `--tags betisier`), and `-v`/`-vv`/`-vvv` for verbosity. `ansible.cfg` sets `stdout_callback = debug` and logs every run to `ansible/run.log`; fact cache lives in `ansible/facts/`.

**Inventory** is dynamic: `ansible/inventory/proxmox.py` and `ansible/inventory/hetzner.py` read the corresponding `tofu state -json` output (via `tofu show -json` run against `../tofu/proxmox` or `../tofu/pangolin`) to build host lists — so `tofu apply` must be current before an inventory-dependent Ansible run picks up new hosts. `ansible/inventory/hosts` holds the static hosts: the Raspberry Pi and the Newt LXC (`newt_lxc` group, host `newt-lxc`; `proxmox.py` only reads VMs). A Hetzner server with no public IPv4 (flip) is emitted by `hetzner.py` with its private IP and a `-o ProxyCommand="ssh … -W %h:%p sylvain@<pangolin public IP>"` that checks the bastion against `ansible/known_hosts` (Pangolin's sshd allows it via `security_ssh_allow_tcp_forwarding: local` in `host_vars/pangolin`); CI does the same (private IP + `ProxyJump=pangolin.sylvain.cloud`, bastion key in the runner's `~/.ssh/config`). Never point Ansible at `flip.internal`: that Pangolin private resource is served by flip's own Newt, so a play restarting newt or docker there cuts its own connection; it is only for manual access through a Pangolin client.

### Secrets (SOPS + Age)

- Two SOPS files hold the secrets: `secrets.sops.yaml` at the repo root (OpenTofu/mise environment) and `ansible/secrets.sops.yaml` (what the playbooks load), both encrypted with Age (`.sops.yaml` lists the recipient age public keys: `perso`, `pro` and `secours` for both files, `github-actions` — the CI's `SOPS_AGE_KEY` — for `ansible/secrets.sops.yaml` only).
- Age private key path is configured in `.sopsrc` (`ageKeyFile: /home/sylvain/.age.key`) — needed to decrypt.
- `mise.toml` auto-loads (and redacts) `secrets.sops.yaml` into task environments via `_.file`.
- In Ansible playbooks, secrets are loaded with:
  ```yaml
  community.sops.load_vars:
    file: "{{ playbook_dir }}/secrets.sops.yaml"
    expressions: evaluate-on-load
    return_method: vars-only
  ```
  `return_method: vars-only` needs ansible-core ≥ 2.21 (pinned in `uv.lock`, which the lint, test and deploy workflows install with `uv sync --locked`) and fails outright below it, instead of handing the secrets back as facts: those only reached the play through the deprecated fact injection, now off (`inject_facts_as_vars = False` in `ansible/ansible.cfg`, `ANSIBLE_INJECT_FACTS_AS_VARS=False` for Molecule; read facts as `ansible_facts[...]`). **Precedence**: the secrets land in the `include_vars` layer, so they **beat** role defaults, `group_vars`/`host_vars`, play `vars:`, the `vars:` of a `roles:` entry, a role's `vars/main.yml` and block/task `vars:`, and lose only to `set_fact`/registered vars, role and include params (the `vars:` of an `include_role`) and extra vars (the play and role-entry `vars:` cases checked on 2.21.5). A key of `ansible/secrets.sops.yaml` must therefore never bear the name of a variable that a playbook or a role sets (hence `host_user_password_hash`, not a generic `password`): prefix it per instance (`prod_planning_*`, `demo_planning_*`) and hand it over in the role entry's `vars:`. `.github/scripts/check_sops_shadowing.py` (Lint workflow; `python -I .github/scripts/check_sops_shadowing.py` from the repo root) fails on any such name.

## Ansible architecture

### Host groups / playbook mapping

| Playbook | Host group | Purpose |
|---|---|---|
| `00-setup.yaml` | `all,!backups,!nas,!pve` | base setup: apt packages, timezone, `sylvain` user + SSH keys from `keys/*.pub`, starship prompt, `ssh_login_notify` (Uptime Kuma/Telegram alert on every SSH login, push URL from the `uptime_ssh_login_urls` output of `pangolin_config`; keys silenced by SHA256 fingerprint in `ssh_login_notify_ignored_fingerprints`, never by comment; `ssh_login_notify_enabled: false` removes the hook, an empty URL only warns) |
| `docker.yml` | `docker` | Proxmox Docker VM — installs Docker, `docker_service`, `host_tuning`, `security`, `borgmatic`, `newt`, then every app role |
| `pangolin.yaml` | `pangolin` | Hetzner Pangolin VM — Docker, `borgmatic`, `security` hardening, `pangolin` role |
| `pi.yml` | `pi` | Raspberry Pi (Debian 13) — Docker, `docker_service`, `host_tuning` (zram, plus the 4 GiB `dphys-swapfile` overflow behind it via `host_tuning_disk_swap_size_mb`), `security`, `borgmatic`, `newt`, `immich`, `beszel_agent`, then tasks tagged `legacy_cleanup` keeping the pre-Pangolin certbot/nginx leftovers absent (the hostname is still `reese`, as in its cron mails) |
| `flip.yml` | `flip` | Hetzner flip server (no public IP) — `nat_client` first, then Docker, `docker_service`, `host_tuning`, `security`, `borgmatic`, `newt`, `flip_planning` ×3 (prod, demo, Keycloak demo), `promptoramix`. Newt credentials come from the `pangolin_config` state (`flip_newt_id`/`flip_newt_secret` outputs), not from SOPS |
| `lxc.yml` | `newt_lxc` | Proxmox Newt LXC — `security` without ufw, auditd or devsec's os_hardening (`host_vars/newt-lxc`: an unprivileged container owns none of them), then `newt_service` (Newt as a plain systemd service, no Docker). Credentials of the `proxmox-lxc` site from the `pangolin_config` state (`proxmox_lxc_newt_id`/`proxmox_lxc_newt_secret` outputs), not from SOPS. A fresh LXC first gets `00-setup.yaml --limit newt-lxc -e ansible_user=root` |
| `nas.yml` | `nas` | Ugreen NAS (UGOS Pro, static in `inventory/hosts`) — `docker_service` in system scope (tags `setup,always`: `/etc/systemd/system/dc@.service` run as root, apps under `/volume1/docker`, the UGOS Docker app's shared folder; see the `docker_service` section), then `borgmatic` in a container (tags `backup,setup`, see the Borgmatic bullets), then role `nas`: pins `maximumNFSProtocol` in `/etc/nfs.json` (UGOS regenerates `/etc/nfs.conf` from it), writes the homelab NFS exports to `/etc/exports.d/homelab.exports` (`host_vars/nas`, always `sync`, client IPs only) and asserts nfs-server is up with no `async` export, then `beszel_agent`, `newt` (site `nas`, credentials from the `pangolin_config` state: `nas_newt_id`/`nas_newt_secret` outputs, not SOPS) and `jellyfin` (`dc@jellyfin`, media from the UGOS shared folder `media` mounted `:ro`; the role asserts the share and its library folders before writing anything, under its own tag only). Jellyfin's compose also runs `jellyfin-traefik` (Traefik, file provider only, no Docker socket, Let's Encrypt by DNS-01 with the OVH key `nas_ovh_application_key`/`_secret`/`nas_ovh_consumer_key`, `acme.json` `0600` root under `docker_base_path`): one name, `https://media.sylvain.cloud`, **`:8443` on the LAN** (UGOS's nginx owns the host's 80/443) and with or without it through the Pangolin client (private resource of that alias, TCP 443 and 8443 on the `newt` network, Traefik listening on both; the public A record `tofu/dns/media.tf` points at the NAS's LAN IP and beats the `*.sylvain.cloud` wildcard). Jellyfin itself sits on the project's `media` network only (fixed subnet, Traefik at `172.30.96.10`, the IP set in Jellyfin's "Known proxies") and keeps `8096` published on the LAN as a fallback. Nothing else of UGOS is touched (no 00-setup, security or packages); shared folders are created in the UI. Run by hand only, never by CI (`resolve_docker_tags.py` prints a notice for a role only `nas.yml` uses) |
| `pve.yml` | `pve` | Proxmox VE host (static in `inventory/hosts`, root without become through `host_vars/pve`: no sudo there; excluded from `00-setup.yaml`) — only `beszel_agent` in `binary` mode with S.M.A.R.T. of `/dev/sda` (the M.2 SATA SSD under every VM and the LXC). The rest of the host belongs to Proxmox and `tofu/proxmox`. Run by hand only, never by CI |
| `pc-nas.yml` | `localhost` | the workstation: `--tags mount` / `--tags umount` (with `-K`; no tag does nothing, every task is tagged `never`) of a NAS shared folder over SMB on `/mnt/nas/<share>` (`pc_nas_share`, default `media`; host from the `nas` inventory entry), for ad hoc tests only — no fstab, password prompted (`no_log`) and handed to `mount.cifs` through a root-only `0600` `credentials=` file under `/run` (tmpfs), written by `command` + `stdin` with `ansible_pipelining: true` (a `copy content=` or an unpipelined module stages the secret in `~/.ansible/tmp`, on disk), deleted right after the mount even on failure (`PASSWD_FILE=/dev/stdin` got `STATUS_LOGON_FAILURE`; `PASSWD` would land in `ps` and `run.log`). With the Pangolin client connected, the NAS IP goes through `nas.internal`, which opens TCP 445 for it (pinned by `pangolin_config`'s tests) |
| `backup.yaml` | `docker,pi,pangolin,flip,nas` then `backups` | reads each host's borgmatic public key, then creates `backup/<host>/.ssh` on the Storage Box and uploads it as that subaccount's `authorized_keys` (see below), plus the key of the read-only `restore-test` subaccount into `backup/.ssh/authorized_keys` (read with `tofu output` in `tofu/pangolin`) |

`00-setup.yaml`, `docker.yml`, `flip.yml`, `lxc.yml`, `nas.yml` and `pangolin.yaml`/`pi.yml` all read the OpenTofu state for `pangolin_config` from the S3-compatible backend (`homelab-tf-state-sylvain` bucket at `s3.eu-west-par.io.cloud.ovh.net`) to pull Uptime Kuma healthcheck-push URLs as Terraform outputs, then pass them into the relevant roles. The SOPS load and the state read are shared: each playbook's first `pre_tasks` entry imports `ansible/tasks/pangolin_config_outputs.yml`, which sets the `terraform_outputs` fact (`no_log`; the state is downloaded once per run, `run_once`, and the registered result reaches every host). A state that cannot be read fails the play, except in `00-setup.yaml`, the only playbook that sets `pangolin_config_outputs_optional: true`: there `terraform_outputs` falls back to `{}` with a warning, so base setup still runs and `ssh_login_notify` only warns. The playbook then `set_fact`s its own `<var>: "{{ terraform_outputs.<output>.value | default('') }}"` — keep that literal form in the playbook, `tofu/pangolin_config/tests/invariants.tftest.hcl` greps the playbooks for it.

### The `docker_service` role (systemd pattern)

Every containerized app runs as a **systemd user service** (a system service on the NAS, see below) via a shared template instantiated per-service:

- `docker_service` role installs a `dc@.service` systemd *user* unit template (`roles/docker_service/templates/dc@.service.j2`) to `~/.config/systemd/user/dc@.service`, and enables lingering for the user (so services survive logout).
- Each app's compose project lives at `{{ docker_base_path }}/<service>` (default `docker_base_path: /opt/apps`), and is started as `dc@<service>.service` (`WorkingDirectory={{ docker_base_path }}/%i`). The unit waits (bounded) for the Docker daemon, pulls only the images that are missing (`ExecStartPre=docker compose pull --policy missing`, so a failed download fails the start job and the Ansible restart handler), then runs `docker compose up --remove-orphans` with no `--pull`: each service's `pull_policy` (default `missing`) decides, so a registry outage at boot cannot stop an app whose image is already present (images are digest-pinned, Renovate bumps them). It restarts every 15 s without a permanent give-up (`StartLimitIntervalSec=0`) and without a `RestartSteps` back-off, whose counter only resets on a manual start or `reset-failed`. An instance that must follow a mutable tag sets `pull_policy: always` on that service (e.g. `flip_planning_image_pull_policy` for the Keycloak bench).
- App roles just template a `compose.yaml` into that directory and `systemd: name=dc@<service> scope=user state=started enabled=true`, notifying a `Restart <service>` handler on change.
- **System scope (the NAS only).** `docker_service_scope: system` (`host_vars/nas`; default `user`, whose rendered unit is byte-identical to before) installs the same template as `/etc/systemd/system/dc@.service` (root, `0644`), run as root: no lingering, no docker group (`sylvain` is not in it on UGOS and `/etc/group` belongs to UGOS). The base path is asserted, never created or chmod'ed (`docker_base_path: /volume1/docker`, the UGOS Docker app's shared folder, SMB-shared to `admin` with `skip smb perm`, so an admin SMB account could read or edit the root-run composes: risk accepted; each app dir is `0700` root). The unit is ordered `After=` `docker_service_system_after` (`docker_serv.service docker.service` on the NAS) without `Wants=`/`Requires=`: UGOS leaves `docker.service` disabled and its `docker_serv` activates `docker.socket` once `/volume1` (the `data-root`) is mounted, so pulling Docker in earlier would start it on the root overlay. `WantedBy=multi-user.target`. An app role on that host uses `scope: "{{ docker_service_scope }}"` with `become: "{{ docker_service_scope == 'system' }}"` (as the role's `Daemon reload` handler does: a bare `become: true` would run `systemctl --user` as root on a user-scope host) in its systemd tasks and handlers; the roles running there (`beszel_agent`, `newt`, `jellyfin`, and `decommission_app`) derive it in their `vars/main.yml` (`<role>_dc_scope`, `<role>_as_root`: root owns the project dir and the compose), and Molecule's `_shared/tasks/verify_app.yml` follows `docker_service_scope` too (root-owned compose, system unit). `nas.yml` gathers no facts: no `ansible_facts['user_uid']`…, a role reads the ids it needs with `getent` (`jellyfin`). Molecule: the `nas` scenario replays `nas.yml` and checks the unit (`systemd-analyze verify`, loaded properties); the `jellyfin` scenario reuses its prepare (fake `media` share, a `renderD128` node made with `mknod`).

### Adding a new app role

Use the **`new-app`** project skill (`.claude/skills/new-app/`) for the full,
current checklist — it also delegates to **`pangolin-route`** and
**`borgmatic-backup`** for their respective pieces, and there's a
**`homelab-reviewer`** agent to sanity-check the resulting diff before
`tofu apply`/`ansible-playbook`. Summary:

- Role skeleton: `defaults/`, `handlers/`, `tasks/`, `templates/` under `ansible/roles/<service>/`. `ansible/roles/trek` and `ansible/roles/wishlist` are the most current reference implementations.
- Compose file is always named `compose.yaml` (not `docker-compose.yml`).
- **Public HTTP routing is entirely OpenTofu-managed, not Docker labels.** Each exposed app gets a `tofu/pangolin_config/website_<service>.tf` declaring its entry of `local.websites` (name, domain, role, target(s), backup flag, its `homepage` link or `homepage = null`: the `homepage_links` output, read by `docker.yml`, is the Homepage role's list of links) and its outputs; `websites.tf` turns every entry into the `pangolin_resource` + `pangolin_target` (+ SSO role binding + healthcheck access token + Uptime Kuma monitors) with `for_each`, so the pins, the maintenance page and the probe settings are written once — Newt only reads the Docker socket to confirm the container is on its network, it doesn't parse any `pangolin.public-resources.*` labels (an earlier pattern, no longer used anywhere in this repo). The container must join the external `newt` Docker network (created by the `newt` role) for Pangolin to reach it. If the app has its own DB, put the DB on a second, internal, service-named network — never on `newt` — declared `internal: true` (no Internet route through it; the app keeps its own through `newt`) unless a container attached *only* to it needs the Internet: karakeep's crawler, immich's ML, meerkat_crm's backend (SMTP) stay non-internal. Changing `internal` on an existing network: `docker compose up` recreates it only when it carries compose's config-hash label, and silently keeps a network created by an older compose as it was — run `docker compose down` once, then check `docker network inspect --format '{{.Internal}}' <network>`. A single-container app needs no private network at all. Two easy-to-miss details: every `pangolin_target` needs `hc_hostname` set explicitly (not inferred from `ip`; `websites.tf` sets it to `ip`, a hand-written target must set it), and multi-target path routing (`sub_targets`) needs the catch-all `"/"` at the *lowest* `priority` number, not the highest. Renaming an entry key or moving a resource into or out of the `for_each` needs a `moved` block, or its access token and push monitor are recreated.
- PUID/PGID come from `ansible_facts['user_uid']`/`user_gid'`, not hardcoded.
- `compose.yaml` (and `.env`) are templated `0600`: they carry secrets, and `dc@` reads them as their owner. `verify_app.yml` asserts it. Every `template`/`copy` of a `0600` file also sets `diff: false`, and every `set_fact` of a push URL or token `no_log: true`: a `--diff` or `-v` run would otherwise write the secret to `ansible/run.log` and the CI logs.
- Databases, redis/valkey and meilisearch get a `healthcheck` whose binary exists in the image (`pg_isready`; `healthcheck.sh --connect` for the official mariadb image; `mariadb-admin ping --host=127.0.0.1` for linuxserver's, which has no `healthcheck.sh`; `redis-cli`/`valkey-cli ping`, with `-a "$$REDIS_PASSWORD"` when a password is set), and whatever needs them waits with `depends_on: {<db>: {condition: service_healthy}}`. Databases also get `stop_grace_period: 60s`: `dc@` stops with `docker compose stop`, whose 10 s default SIGKILLs them. Molecule checks all three through `_shared/tasks/verify_compose_services.yml`.
- **Resource limits doctrine** (the Docker VM has 3 cores / 12 GiB on a rotational disk; aggregate CPU use is a few percent, so quotas only add latency):
  - Every service gets a `mem_limit` (hard cap). Size it at ~2× the measured peak (`memory.peak` in the container's cgroup), never below. A container pinned at its cap is not OOM-killed, it has its page cache evicted and thrashes the disk.
  - Databases (and anything measured at its cap) also get `mem_reservation` ≈ the peak: on cgroup v2 it becomes `memory.low` and protects their page cache.
  - **No `cpus:` on DBs, redis/valkey or interactive services.** A CFS quota below 1 core throttles any single-threaded burst even on an idle host.
  - Only batch-capable containers (OCR, document conversion, Celery workers) get `cpus: 2.00` + `cpu_shares: 512`: the cap always leaves one core to the rest, the weight makes them lose under contention and costs nothing when idle.
  - Check images' default worker counts (`GUNICORN_NUM_WORKERS`, `pm.max_children`…) against the cap: gramps defaulted to 8 gunicorn workers of 170 MiB under a 1 GiB cap and OOM-looped.
- Backups use Borgmatic, not Restic. There is **one** config template for every app, `ansible/roles/borgmatic/templates/app.yaml.j2`, rendered by `ansible/roles/borgmatic/tasks/app.yml`: an app role calls it with `include_role: name=borgmatic tasks_from=app.yml` (+ `apply: tags: backup`) and `borgmatic_app_*` vars (name, sources, DB dumps, excludes, target, passphrase, healthcheck URL — documented in the role's `defaults/main.yml`); it never ships its own borgmatic template or repo-create task. Non-obvious structural rules the shared template keeps (deviating from these breaks Borgmatic):
  - Retention keys (`keep_daily`/`keep_weekly`/`keep_monthly`/`keep_yearly`) are **top-level**, not nested under `retention:`.
  - `checks:` (with `name`/`frequency`) is **top-level**, not nested under `consistency:`.
  - Use `commands:` with `before/after: action` + `when: [create]` hooks, not `before_backup`/`after_backup`/`on_error`.
  - `archive_name_format` is `'<service>-{now:%Y-%m-%dT%H:%M:%S}'` — no `{hostname}` prefix.
  - `compression: zstd,10`, not `auto,zstd`.
  - Target: `<service>_backup_borgmatic_target: "{{ backup_storage_box_url }}/<service>"` in the role defaults (`backup_storage_box_url` is a group var: `ssh://<subaccount>@<server>/.`, the host's subaccount), passphrase `<service>_backup_encryption_passphrase: "{{ backup_passphrase }}"` there too — not in `host_vars`.
  - Never back up a live database directory: PostgreSQL/MySQL are dumped by the client inside the DB container (`borgmatic_app_postgresql_databases` / `_mysql_databases`), SQLite files copied by the host's `sqlite3 ".backup"` in a `before` hook into `/var/lib/borgmatic-sqlite/<app>/` (`borgmatic_app_sqlite_databases`, globs resolved at deploy time; their live copy is excluded). Never borgmatic's own `sqlite_databases`: its streamed `.dump` holds a read lock for the whole upload and froze Pangolin. MySQL/MariaDB dumps go through `/usr/local/bin/borgmatic-docker-dump`, since borgmatic 2.1 hands the client a host-side `--result-file`; the client is `mariadb-dump` unless an entry sets `dump_command` (every database here is MariaDB, and linuxserver's `mysqldump` warns it is deprecated).
  - `exclude_patterns` are borg `fm:` patterns matched from the start of the archived path: `'*.log'` works anywhere, a relative `'cache/*'` matches nothing — app-specific excludes are absolute paths.
  - **On the NAS** (`borgmatic_install: container`, `host_vars/nas`; UGOS has no apt nor pipx) the `borgmatic` role installs nothing: `tasks/container.yml` templates the official image's compose (`ghcr.io/borgmatic-collective/borgmatic`, digest-pinned, grouped by Renovate with the pipx `borgmatic_version`; borg 1.4 and `sqlite3` inside) under `docker_base_path/borgmatic`, and `borgmatic_bin` becomes the wrapper `/volume1/docker/borgmatic/borgmatic` (`docker compose run --rm`), which the usual `borgmatic.service`/`.timer` (02:30) and `tasks/app.yml`'s `repo-create` call. Everything a config names (itself, `borgmatic_config_dir`, the SSH key `backup_storage_box_ssh_key_path`, the sources under `docker_base_path`, `/var/lib/borgmatic-sqlite`) is mounted at the same path in the container, so `app.yaml.j2` is shared unchanged (`local_path` is `borgmatic_borg_bin`); borg's cache/security dirs and borgmatic's check state are bind-mounted to persist. No dc@: a backup is a one-shot job. Molecule (`nas`, `jellyfin`) overrides `borgmatic_bin` with the shared stub, never pulling the image.
- Each backed-up host (docker, pi, pangolin, flip, nas) has its own Storage Box subaccount (`tofu/pangolin/storage_box_subaccounts.tf`), whose home is `backup/<host>`: root on one host can neither read nor delete another host's repositories, and none can delete the 9 daily snapshots (`snapshot_plan`). `backup_storage_box_url` points at the host's subaccount (`backup_storage_box_subaccount` in its `host_vars`, from the SOPS key `backup_storage_box_subaccounts`, copied from the `storage_box_subaccounts` output), and Borg creates each app's repository there itself — no folder to register per app. The borgmatic role generates root's key on the host (`backup_storage_box_ssh_key_path`); `ansible/backup.yaml` (Storage Box restricted shell: `gather_facts: false`, `raw`, `scp` from the controller) creates `backup/<host>/.ssh` and uploads that key as the subaccount's `authorized_keys`, for every host of `backup_storage_box_hosts` (`ansible/host_vars/backups`, pinned against the subaccounts by `tofu/pangolin`'s tests). Order for a new host: the host's playbook with `--tags setup` (key generated, no app role: an app's `repo-create` would already hit the subaccount), then `backup.yaml`, then the full playbook.
- Register the new role's systemd unit as `dc@<service>` — don't template a bespoke `.service` file, `docker_service` already provides the generic template.
- Finally, add the role to the right playbook (`docker.yml` for the Proxmox host, `pangolin.yaml` for the Pangolin VM, etc.) with sensible tags (`<service>,app`), and wire its `<service>_backup_healthcheck_url` into that playbook's `pre_tasks` alongside the others.

### App data on the NAS

Apps can keep their data on the Ugreen NAS (NFSv3 export mounted on the
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
  borg can't read it. UGOS creates every file and directory `0777` whatever
  the umask, but honours an explicit chmod: give each NAS path an explicit
  `mode:`.
- UGOS Pro 1.20 serves NFSv3 only (`nas_storage_nfs_version: "3"`): NFSv4.1
  can be enabled but UGOS declares no v4 pseudo-root. The VM's export is
  published by `nas.yml` (`host_vars/nas`), always `sync`; a rule added in the
  UI instead has "Async" ticked by default.
- Postgres/MariaDB data dirs may live there; **SQLite (and any mmap/lock-based
  embedded DB) never does** — it stays on the local disk.
- Every NAS-backed container gets `cgroup_parent: {{ nas_storage_slice }}`:
  that slice is ordered after the mount, so at VM shutdown the containers stop
  before the NAS is unmounted and the network goes down (a `hard` mount would
  otherwise hang Postgres' last checkpoint).
- A `dc@<service>.service.d/nas-storage.conf` user drop-in with
  `ExecStartPre={{ nas_storage_wait_command }} <timeout>`: at boot the VM is
  up before the NAS, and without the wait every `docker compose up` fails on
  the automount (30 s) with a Docker bind-mount error, retried by dc@ forever.
  dc@'s `TimeoutStartSec` (300 s) covers all its `ExecStartPre`: its Docker
  wait (up to 120 s) and the pull come first, so keep the NAS wait at 150 s
  or less.
- Borgmatic (`borgmatic` role, `tasks_from: app.yml`): NAS file dirs in
  `borgmatic_app_source_directories`, the DB data dir **not** (dumped through
  `borgmatic_app_postgresql_databases`),
  `borgmatic_app_extra_options: {source_directories_must_exist: true}`, and
  `borgmatic_app_before_commands: ["{{ nas_storage_wait_command }} 30"]`
  (runs before borg reads the NAS): without it a dead NAS blocks the single
  `borgmatic.service`, hence every app's backup.
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

`flip_planning` is applied three times by `flip.yml`: production
(`flip-planning.sylvain.cloud`), the demo (`demo-planning.sylvain.dev`) and
the Keycloak demo (`demo-planning-kc.sylvain.dev`, `demo_planning_kc`). There is one role, not two — duplicating a role
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
  of the same name, nor a SOPS key of the same name.** `vars:` on a `roles:`
  entry wins over the role defaults and `host_vars`, but it **loses to a
  `set_fact`, to `include_vars` and to the keys loaded from
  `ansible/secrets.sops.yaml`** (`load_vars` registers them in the
  `include_vars` layer since ansible-core 2.21): checked, not assumed. Hence
  `prod_planning_*` / `demo_planning_*` in SOPS, each handed to its instance,
  and never a `flip_planning_*` key for a variable an instance overrides — the
  flip_planning Molecule converge fails on one. An override
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

### Pausing an app

An app kept but unused (Paperless-ngx today) is paused, not removed:
`docs/runbooks/app-en-pause.md`. Four switches move together — the role's
`<service>_enabled: false` in `host_vars` (unit stopped and disabled, restart
handler skipped, borgmatic config removed so the nightly dump cannot fail;
compose, data and borg repository kept), `enabled = false` in the app's
`local.websites` entry (resource disabled, healthcheck **and** backup monitors
paused), the list of paused apps in `pangolin_config`'s invariants, and
`"paused": true` in `.github/restore-test/apps.json` (skipped by the scheduled
restore test; `tofu test` requires it exactly on the apps whose backup monitor
is paused). Only `paperless_ngx` has the switch so far; its Molecule
`side_effect.yml` goes through both states.

### Removing an app role

Use the **`remove-app`** project skill (`.claude/skills/remove-app/`) for the
full checklist — it's the reverse of `new-app` and touches the same files.
Summary: run the reusable `ansible/roles/decommission_app` role (registered
in `docker.yml`/`pi.yml`/`flip.yml`/`nas.yml` under `tags: [decommission, never]`, so it only ever
runs when invoked explicitly via `--tags decommission`) to stop/disable the
`dc@<service>` unit and delete containers/volumes/data/borgmatic config, then
delete the role directory, deregister it from the playbook (role entry +
healthcheck `set_fact` line), remove its `host_vars`/secrets
entries, delete its `tofu/pangolin_config/website_<service>.tf`, its line in
`websites.tf`'s `local.websites` and its slug from `roles.tf`'s `apps` list
(then `tofu apply`), and finally grep the whole
repo for the service name to confirm nothing was missed. That last step
matters: the `photoprism` removal (commit `7e848ed`) skipped it and left
orphaned `host_vars`/`secrets.sops.yaml` entries behind for months.

### Config layering

- `ansible/group_vars/all/variables.yml` — shared defaults (`docker_base_path: /opt/apps`, `borgmatic_config_dir`, `newt_endpoint`, SSH user, etc.), plus vendored-role var files (`geerlingguy.docker.yml`). devsec.hardening's variables are not there: the `security` role passes them to `include_role` from its own `security_*` defaults.
- `ansible/host_vars/<host>/` — per-host overrides (`docker`, `pangolin`, `pi`, `nas`, `pve`, `backups`). Note this is `host_vars/<hostname>`, matching the dynamic-inventory-generated host name, not a role/group name.
- Ansible collections live in `ansible/collections/ansible_collections/` and Galaxy roles in `ansible/galaxy_roles/`, both populated from `ansible/requirements.yml` (not committed as vendored source — reinstall via `ansible-galaxy install -r requirements.yml` if missing, or set up through mise/CI).

## OpenTofu architecture

- `tofu/proxmox/` — Proxmox VE provider: the Docker VM (`proxmox_docker_vm.tf`, read back as inventory by `ansible/inventory/proxmox.py`) and the Newt LXC container (`proxmox_newt_lxc.tf`; static in `inventory/hosts`, configured by `ansible/lxc.yml`).
- `tofu/pangolin/` — Hetzner Cloud provider: the Pangolin VM, the flip VM (private network only) and the network route that makes Pangolin its NAT gateway, and Hetzner Storage Box config (see `STORAGE_BOX_SETUP.md` there for the manual setup steps SSH/rsync require). The state bucket is not here but in `tofu/s3_state/` (OVH Object Storage).
- `tofu/keepass_backup/` — OVH Object Storage bucket (Object Lock, versioning, lifecycle) for the restic repository of the dotfiles `keepass_backup` role, with a writer key (workstation, cannot delete data) and an admin key (yearly prune, kept in KeePassXC). No homelab app uses it. See its README.
- `tofu/pangolin_config/` — Pangolin-side application config (roles, rules, private resources, per-app `website_*.tf` files declaring each public app as an entry of `local.websites`, from which `websites.tf` generates the resources, targets and Uptime Kuma checks) applied against the running Pangolin instance, separate from the VM provisioning itself. Its state is what `00-setup.yaml`/`docker.yml`/`flip.yml`/`lxc.yml`/`nas.yml`/`pangolin.yaml`/`pi.yml` read at Ansible time for healthcheck and SSH-login push URLs (and, for `flip.yml`, `lxc.yml` and `nas.yml`, the Newt credentials of the `flip`, `proxmox-lxc` and `nas` sites). It reads `tofu/pangolin`'s state (`remote_state.tf`) for flip's private IP, so `tofu/pangolin` is applied first. Every public resource is declared there — there is no hand-made public resource left (`SSH PI`, the last one, was deleted in favour of the private `pi.internal`; Proxmox and the NAS are private too since, `pve.internal` and `nas.internal` in `private_resources.tf`, like `media.sylvain.cloud` (an alias that is also a public A record to the NAS's LAN IP, `tofu/dns/media.tf`), served by the NAS's own Newt on site `nas` and opened to the `pangolin_role.jellyfin` members), and the coverage precondition in `rules.tf` fails the plan on any enabled resource missing from `local.managed_resources` (derived from `local.websites`), so a resource created in the UI must be deleted or disabled there before the next apply. Optional+computed attributes of `pangolin_resource` (`mode`, `ssl`, `enabled`…) come from `local.resource_pins` (`resource_defaults.tf`); an entry may override `enabled` (false pauses the app: resource disabled, healthcheck and backup monitors paused, see « Pausing an app »); only paperless does today. `headers` is in `ignore_changes` on all of them, deliberately (`websites.tf`): a `for_each` cannot vary its lifecycle and the provider cannot remove a header anyway, so a header set by hand in the UI no longer shows in a plan. The two VPN exit nodes, site resources `vpn` and `vpn-flip` in `gateway` mode, cannot be declared (provider 1.6.1 only knows `host`/`cidr`/`http`): they are made in the UI and audited by `terraform_data.vpn_gateways` (`private_resources.tf`), which fails the plan if one is missing, not in `gateway` mode, or, for `vpn-flip`, not on the `flip` site. Any in-place update of a `pangolin_site_resource` wipes its bindings: provider 1.6.1 sends empty `roleIds`/`userIds`/`clientIds` and Pangolin replaces them (non-admin roles, users, OLM clients), while the state still holds them, so the access is gone until the next apply (seen on `jellyfin` in #869). Every `pangolin_site_resource_role`/`_user`/`_client` therefore carries `lifecycle { replace_triggered_by = [pangolin_site_resource.<x>] }` (the binding is removed before the update, re-added after it, in the same apply), enforced by the `site_resource_bindings_follow_their_resource` test. A failed update leaves the binding removed (re-run the apply), and a binding made in the UI is wiped too with nothing to restore or report it: declare every wanted binding. Still, always run a new plan after an apply that changed a private resource: it must be empty.
- `tofu/dns/` — OVH DNS zone records (`ovh_domain_zone_record` / `ovh_domain_zone_redirection`, not Cloudflare): the Pangolin A records (`*.sylvain.cloud`, the `sylvain.cloud` apex, `*.sylvain.dev`, and the `sylvain.dev` apex while `sylvain_dev_apex_to_pangolin` is true) read from `tofu/pangolin`'s state, the GitHub Pages challenges, the betisier redirect, and the `sylvain.dev` apex Google Search Console TXT record (`search_console.tf`). Cloudflare only appears in the Pages modules (`tofu/ref`, `tofu/site`, `tofu/1y`).
- `tofu/github/` — GitHub-side config: the Actions secrets of this repo (SOPS Age key, CI deploy key, OLM credentials read from `pangolin_config`'s state; the `restore-test` environment's secrets, from `tofu/pangolin`'s and `pangolin_config`'s states and `backup_passphrase`) and the `planning-equipes` and `promptoramix` repositories themselves — creation, visibility, `main` branch protection. The settings the provider can't reach (fork PR approval, private vulnerability reporting, GHCR package visibility, Renovate/GitGuardian) are a checklist in `tofu/github/README.md`.
- `tofu/ref/` — the referral site ref.sylvain.dev (repo `sylvainmetayer/ref`, 11ty on Cloudflare Pages): GitHub repository, Cloudflare Pages project + custom domain, Web Analytics site, and the OVH CNAME overriding the `*.sylvain.dev` wildcard. Needs `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID` in `secrets.sops.yaml`; see its README.
- `tofu/site/` — the personal site sylvain.dev (repo `sylvainmetayer/site`, 11ty on Cloudflare Pages, same pattern as `tofu/ref`, the pre-existing repository imported once, its `import` block since removed): the GitHub repository (secret scanning, Dependabot alerts without Dependabot PRs, a `main` ruleset requiring a PR and green checks, no bypass), its Actions secrets (Pages deploy hook for the daily build, SonarCloud token), Pages project `sylvain-dev` + custom domain `www.sylvain.dev` (webmention.io token as a production-only secret), the pre-existing Web Analytics site (imported), and the OVH CNAME for `www`. Pages only accepts an apex inside a Cloudflare zone, so the apex A record lives in `tofu/dns/pangolin.tf` (`sylvain_dev_root`, behind `sylvain_dev_apex_to_pangolin`) and Traefik answers it with a 301 to www through `pangolin_domain_redirects` (`ansible/host_vars/pangolin/variables.yaml`, routers in the pangolin role's dynamic config), which also serves a self-unregistering service worker in place of the old site's. Its README holds the Netlify cut-over order.
- `tofu/1y/` — the short-URL site r.sylvain.dev (repo `sylvainmetayer/1y`, 11ty on Cloudflare Pages, formerly Netlify): Cloudflare Pages project + custom domain, the OVH CNAME, and the GitHub repository itself (imported through an `import` block, settings aligned on `tofu/ref`, Dependabot PRs off in favour of Renovate). Same prerequisites as `tofu/ref`; the Pages build reads Node from `wrangler.toml`, and a precondition fails the plan when it drifts from the repo's `mise.toml`. See its README for the one-off DNS import of the Netlify-era record.
- All backends are S3-compatible object storage (`homelab-tf-state-sylvain` bucket at `https://s3.eu-west-par.io.cloud.ovh.net`), not native AWS — `backend "s3" { endpoints = { s3 = ... } }`.
- The states of `tofu/pangolin`, `tofu/github`, `tofu/s3_state` and `tofu/keepass_backup` are encrypted by OpenTofu (`encryption.tf`: AES-GCM, PBKDF2 key from `var.state_encryption_passphrase`, i.e. `TF_VAR_state_encryption_passphrase` from the root `secrets.sops.yaml` that mise loads). `tofu/dns` and `tofu/pangolin_config` decrypt `tofu/pangolin`'s state for their `terraform_remote_state.pangolin` (`remote_state_data_sources`) and keep their own state in clear: Ansible reads `pangolin_config`'s on S3. `ansible/inventory/hetzner.py` runs `tofu show` in `tofu/pangolin`, so it needs the same environment. Tests pass a dummy passphrase in their `variables {}` block. There is no `unencrypted` fallback any more (all three migrated on 2026-10-23): a state in clear, or encrypted with another passphrase, is refused.

## CI (GitHub Actions)

- `.github/workflows/lint.yaml` — `ansible-lint`, `.github/scripts/check_sops_shadowing.py` (no key of `ansible/secrets.sops.yaml` or `fake_secrets.yml` may bear the name of a play, `roles:` entry, block, task or `import_role` `vars:`, nor of a role's `vars/`), the unit tests of the CI scripts (`.github/scripts/test_*.py`, `python -I -m unittest discover -s .github/scripts -p 'test_*.py'`: `resolve_docker_tags.py` decides what a merge deploys, `select_tests.py` what a PR tests), `tofu fmt -check` and `tofu validate` (pangolin, proxmox, pangolin_config, dns, github, ref, s3_state, keepass_backup, site, 1y) on every PR.
- `.github/workflows/lint.yaml`, job `CI lint` — zizmor (actions pinned by SHA, template injection, persisted checkout credentials), actionlint (`.github/actionlint.yaml` declares the `ubuntu-26.04` label) and hadolint on the Molecule Dockerfile (`.hadolint.yaml`), all as pinned binaries checked by sha256. Locally: `mise run lint-ci`. Every `actions/checkout` sets `persist-credentials: false`; a matrix value reaches a `run:` through `env:`, never as `${{ … }}` inside the script. Secrets: `mise run secrets-scan` (gitleaks over the whole history, `.gitleaks.toml` lists each known false positive with its reason) and `mise run install-hooks` (gitleaks pre-commit hook on staged changes).
- `.github/workflows/deploy-docker-app.yaml` — on a push to `main` touching `ansible/roles/**` or a host playbook (or by hand, `workflow_dispatch` with forced `tags`), opens the OLM tunnel and runs the playbooks with the tags `resolve_docker_tags.py` derives from the changed files. Runs are serialized (`concurrency: deploy-docker-app`, OLM refuses a second connection), and GitHub keeps one **pending** run per group: a third push cancels the pending one. So the changed files are diffed from the head of the **last successful push run** (read through the API, `actions: read`), not from the push's own `before`: the next run catches up a cancelled or failed one, a run failing halfway is retried whole (idempotent), dispatch runs never count as a base, a re-run of a commit older than that base deploys nothing (it would roll back), and an API error fails the run rather than deploy only the push. The files are those of every commit of the range plus the net diff (a revert of a half-applied commit nets to nothing), and each host's `Deploy` step runs even when an earlier one failed (`!cancelled()`), or a host that stays down would block the others in every run.
- `.github/workflows/test.yaml` — discovers `ansible/molecule/*/molecule.yml` and `tofu/*/tests/` and runs one matrix job per Molecule scenario and per tested Tofu module (see "Tests" above). On a PR, only the suites the changed files reach (`.github/scripts/select_tests.py`, read from the tree: a scenario's roles followed through meta dependencies and `include_role`/`import_role`, the paths its files reach — host_vars, another scenario, a playbook —, a module's `file()`/`fileset()` reads; `_shared`, `group_vars`, `requirements.yml`, `uv.lock` rerun every scenario, `mise.toml` every module, `test.yaml` or the script everything, an unclassified file everything, docs nothing); a `full-tests` label, `workflow_dispatch` and the nightly run (03:30 UTC, `schedule`; no `push` trigger) run the full matrix. A dependency the script cannot read (a path built at runtime) is missed on the PR and caught by the nightly: teach it to `select_tests.py`. The `Molecule image` job builds `homelab-molecule:debian13` once into the GitHub Actions cache (buildx, `type=gha`, scope = Dockerfile hash), each Molecule job loads it from there. `Tests` stays the one required check, green when the matrices are empty. A new push to a PR cancels its running Tests and Lint runs (`concurrency`).

- `.github/workflows/path-bypass-review.yaml` — on a PR that bumps a version in `tofu/pangolin_config/path_bypass_images.json`, writes the release notes/sources to re-read in the run summary and waits for an approval of the `relecture-chemins-publics` environment (see the path ACCEPTs note below).

- `.github/workflows/restore-test.yaml` — on the 1st and the 15th, restores on a runner the latest archive of every borg repository of `.github/restore-test/apps.json` (`host`/`repo`/`role`, kept equal to the backup monitors by `pangolin_config`'s tests): fails on an archive older than 28 h (one missed night), extracts a sample, replays SQL dumps in a throwaway container of the role's DB image, runs SQLite `integrity_check`; a last job pushes the overall result to the single `Restore test` Uptime Kuma monitor (20 days). Secrets live in the `restore-test` environment (main only, not `production`: no age key): the **read-only** `restore-test` Storage Box subaccount (home `backup/`, `tofu/pangolin/storage_box.tf`, key uploaded by `ansible/backup.yaml`, hence `borg --bypass-lock`) and `backup_passphrase`. See `.github/restore-test/README.md`.

- `.github/workflows/borg-check.yaml` — once a quarter (the 5th, 02:00 UTC), `borg check --archives-only --verify-data` (borgmatic's `data` check) on every repository of `apps.json`, one at a time, with the restore test's read-only sub-account and environment (shared access steps: `.github/actions/storage-box-readonly`); a failed scheduled run is its only notification (no push monitor can wait a quarter).

- `.github/workflows/ping.yaml` — manual (`workflow_dispatch`) connectivity test that starts an `fosrl/olm` (Pangolin's Outline-like mesh client) container on the runner, points the runner's system DNS at the OLM DNS proxy, and validates both public internet access and reachability of a private Pangolin resource (`docker-apps.internal:22`). Useful as a template if debugging OLM/Pangolin tunnel DNS issues — the key gotcha documented inline: `OVERRIDE_DNS=true` only rewrites `/etc/resolv.conf` *inside* the OLM container (different mount namespace), so the runner's own resolver must be repointed manually at `100.96.128.1`.

## Notes / gotchas

- Host hardening (`security` role, on pangolin, flip, docker and pi, and on the Newt LXC without ufw, auditd and os_hardening): ufw rules, fail2ban (journal backend), unattended-upgrades and a send-only msmtp relay (Infomaniak account `pangolin_smtp_*`, root aliased to `pangolin_le_email`; it replaces the exim4 that logwatch used to pull) are in-house. sshd and OS hardening come from `devsec.hardening` (os_hardening + ssh_hardening, pinned in `requirements.yml`) on every host running the role; there is no in-house sshd drop-in or sysctl hardening path any more. devsec is applied partially: `security_devsec_sysctl_overwrite` keeps `ip_forward` at 1 (Docker, Pangolin's NAT), `rp_filter` loose and IPv6 forwarding at 1 as Docker sets it, and the role asserts it before devsec reloads its sysctl (immediately, unlike the role's own boot-time file: `disable_ipv6` therefore stays in the boot-only `99-hardening.conf`; `fs.file-max` is set on no path: kernel default, reached only after a reboot on a host that booted with the old 65535, Pangolin included); `ssh_client_hardening` stays off (borgmatic's SSH client); AllowTcpForwarding comes from `security_ssh_allow_tcp_forwarding` (`local` on the bastion). The algorithms sshd offers (kex, ciphers, MACs, host keys and sizes) are pinned, exact match, by the ssh-audit policy `ansible/molecule/security/files/ssh-audit-policy.txt`: checked by every `security*` scenario's verify (`ansible/molecule/security/tasks/verify_ssh_audit.yml`, ssh-audit baked into the Molecule image) and on the real hosts from the LAN by `mise run ssh-audit`; a devsec or OpenSSH bump that changes them fails Molecule until the policy is updated. devsec skips sysctl inside containers, so Molecule cannot prove the kernel values — only the overwrite.

- SSH access to the Raspberry Pi and the Docker VM is local-network only: they are LAN hosts, their `security` host_vars open 22/tcp to `192.168.1.0/24` only (the `from` of `security_ufw_allowed_ports`), never ban the LAN (CI arrives through the newt LXC, 192.168.1.200), whitelist `vfat` for devsec (`/boot/efi`, `/boot/firmware`) and reboot after kernel updates at 05:00 (docker) and 05:30 (pi). The Pi's arm64 kernel caps `vm.mmap_rnd_bits` at 24 (`security_devsec_sysctl_host`). Root no longer logs in over SSH anywhere: the Immich remote worker mounts the Pi's library as `sylvain` with a sudo SFTP server (`compose/immich/README.md`). Docker-published ports bypass ufw, so the Pi's Immich, Postgres, Valkey and timelapse ports stay reachable from the LAN.
- Every public Pangolin resource only lets FR and DE through (`tofu/pangolin_config/rules.tf`; `apply_rules = true` on all of them, pinned by the `every_public_resource_applies_its_rules` test, which also pins Betisier, nextcloud and Promptoramix as the only resources without SSO; `php_lockdown.tf` temporarily forces nextcloud behind the SSO and disables the Monica path ACCEPTs until a critical PHP vulnerability is patched; FreshRSS has none, it is read in the browser only, its API off), except the rules evaluated before the country rules. Priority 1 is a DROP of any path holding a backslash (`backslash_guard`) on every resource that has a path rule, since Pangolin does not normalise `\` and Node turns it into `/`. Priorities 2-9 hold the path ACCEPTs that answer from anywhere without SSO, protected by the app's own secret: share links, calendar feeds, client APIs, MCP/OAuth, and Promptoramix's whole `/*` (called by the Linkx tournament's Supabase edge functions from anywhere, guarded by its HMAC signature check — the one deliberate whole-app bypass). Each app lists them next to its resource as `local.<app>_*_paths` (path => priority), aggregated in `local.path_bypasses`. Those paths were read off one version of each third-party image, noted in `tofu/pangolin_config/path_bypass_images.json` (the `path_bypasses_follow_their_image` test checks it against the compose files and that every `local.path_bypasses` resource is listed or explicitly exempted). Renovate bumps that file together with the compose (custom manager), so no hand commit is needed; `.github/workflows/path-bypass-review.yaml` then holds the PR on the `relecture-chemins-publics` environment (required reviewer, `tofu/github/environments.tf`) until someone reads the release notes and the listed sources and approves the run in the GitHub UI. If a route moved, fix the app's `_paths` in the same PR before approving. Every path ACCEPT goes through `local.path_bypasses`, Karakeep's public lists, TREK's OAuth surface and the planning `/mcp/*` and KC `/auth/*` rules included (`pangolin_resource_rule.path_bypass["<Resource name> <path>"]`; a rule leaving a standalone resource for it needs a `moved` block, see `moved.tf`). Priorities 2-9 also hold the only standalone path rule, TREK's `/mcp` PASS (`trek_mcp`: skips the country rules, still requires SSO or a Pangolin access token; `local.standalone_path_rule_resources` keeps its backslash guard, and the `tied_rules_share_their_action` apply run fails if any PATH rule's resource has none), and the home-IP ACCEPTs at 9. Rules sharing a priority on one resource must share their action (`tied_rules_share_their_action` test). For a trip, add the country with an end date to `travel_countries` (`tofu/pangolin_config/variables.tf`) and apply: it gets its own priority (20), and the first apply after that date closes it again (the `travel_countries_stale` check then asks for the entry to be removed). Nothing applies `pangolin_config` on a schedule, so it stays open until someone does.
- The Pangolin `newt` container must share a Docker network with any app it fronts (socket-proxy access requirement).
- Monitoring is Beszel (`docs/architecture.md`, « La supervision »): hub role `beszel` on the Docker VM, agent role `beszel_agent` on every host (`dc@beszel_agent` on docker/pi/flip, the same mode `dc` on the NAS, where `docker_service_scope: system` makes it a root system unit under `docker_base_path`, `docker compose up -d` on Pangolin, a systemd binary on the newt LXC and on the Proxmox host, `pve.yml`, which also reads S.M.A.R.T.). Agents dial the hub (no listening port): LAN hosts on `192.168.1.216:8090` (published by Docker, so before ufw: only the Beszel account guards the UI there), Pangolin and flip through the public resource's `/api/beszel/agent-connect` PASS with a per-agent Pangolin access token (`beszel_agent_hub_headers` output). The hub's `config.yml` is authoritative: a host removed from the SOPS dict `beszel_agent_tokens` loses its history. It only knows systems: alerts (`beszel_alerts`) and the Telegram/e-mail channels (`user_settings`; SOPS `beszel_telegram_bot_token`/`beszel_telegram_chat_id`) are written by the role through the hub API at `127.0.0.1:8090`, logged in as the admin account (so `beszel_admin_password` must stay its password), authoritative too (tag `beszel_alerts`; test message: `--tags beszel_alerts_test`). The agent never mounts the Docker socket: a `wollomatic/socket-proxy` sidecar (GET-only allowlist `beszel_agent_socket_proxy_allow_get`: container logs by hex ID yes, inspect no — Beszel strips only `Config.Env` from it, command args and labels would pass) does. The hub's `CONTAINER_DETAILS=true` serves the UI's container sheet, logs relayed on demand (last 200 lines, never stored) to any Beszel account with access to the system; its inspect pane stays empty (403 at each agent's proxy, logged on every sheet opening). Binary-mode hosts (newt LXC, pve) have no Docker, hence no container sheet, and no systemd service logs either: their unit's `DynamicUser` is in no journal group, so the agent finds the system journal unreadable and turns them off (`SupplementaryGroups=systemd-journal` would open the whole journal, not just `SERVICE_PATTERNS`).
- GeoLite2 (the geo filter of every public resource) is refreshed weekly on Pangolin by `geoipupdate.timer` (pangolin role: the official MaxMind image, pinned; free account, `pangolin_maxmind_*` in `ansible/secrets.sops.yaml`), which restarts the `pangolin` container only when the database changed and pushes to the `GeoIP Pangolin` monitor (`uptime_cron_geoip_url`).
- The running Pangolin server was created from an old Packer snapshot (Packer has since been removed from the repo). `image` is in the `ignore_changes` of `hcloud_server.pangolin` (`tofu/pangolin/pangolin.tf`), so the plan stays clean; a rebuild starts from plain `debian-13` + `user_data.yaml` (user `sylvain` only), then `00-setup.yaml` and `pangolin.yaml`, then a restore of `/opt/pangolin` (config, SQLite DB, Let's Encrypt certificates) from its Borg repository. A rebuilt host has a new SSH host key: read it on the host (`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`, Hetzner console) and replace its line in `ansible/known_hosts`, never through `ssh-keyscan` across the network — Ansible (`ansible.cfg` `ssh_args`, `StrictHostKeyChecking=yes`), the bastion jump of `hetzner.py` (a `ProxyCommand`, so the jump checks the same file) and the CI all refuse any other key.
