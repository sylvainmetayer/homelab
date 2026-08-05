---
applyTo: "ansible/roles/**,ansible/docker.yml,ansible/pangolin.yaml,ansible/pi.yml,ansible/host_vars/**"
description: Checklist for deploying a new self-hosted app on this homelab's Proxmox docker host.
---

# Deploy a new app on the homelab

Every app added to this repo touches the same ~7 files (verified against the
`gramps`, `homelable` and `flip_planning` additions). Skipping one is
the most common source of a "works but isn't backed up" or "deployed but
unreachable" app. Use `ansible/roles/gramps` and
`ansible/roles/homelable` as your primary reference implementations — they're
the freshest and match current conventions exactly (unlike some older roles).

Pick a service slug once and use it consistently: `snake_case` for Ansible
role/variable names, `kebab-case` for the Pangolin role slug in
`tofu/pangolin_config/roles.tf`.

## 1. Ansible role skeleton

Create `ansible/roles/<service>/` with `defaults/`, `handlers/`, `tasks/`,
`templates/` (mirror `ansible/roles/gramps/`):

- `defaults/main.yml`: `<service>_base_path: "{{ docker_base_path }}/<service>"`
  plus placeholder backup vars (real values go in `host_vars`, see step 4).
- `templates/compose.yaml`: the container that must be publicly reachable
  joins the **external** `newt` network; anything DB/backend-only goes on an
  **internal**, service-named network only — never put a database on `newt`.
  Container names matter: they're what the Pangolin target's `ip`/`hc_hostname`
  will reference in step 6.
- `templates/env.j2` (or `env.docker.j2`): templated `.env`, mode `0600`.
- `templates/borgmatic-<service>.yaml.j2`: **don't write this from generic
  borgmatic docs** — copy the structure from `ansible/roles/betisier/templates/borgmatic-betisier.yaml.j2`
  exactly (see `.github/instructions/borgmatic-backup.instructions.md` for the
  non-obvious structural rules this repo requires).
- `tasks/main.yml`, in order: ensure app folders exist → template
  `compose.yaml` (notify `Restart <service>`) → template env file → borgmatic
  block (`when: <service>_backup_enabled`, tags: `backup`) → `systemd: name=dc@<service> scope=user state=started enabled=true`.
- `handlers/main.yml`: a `Restart <service>` handler that
  `systemd: state=restarted name=dc@<service> scope=user daemon_reload=true`.

Don't template a bespoke `.service` file — `docker_service` already provides
the generic `dc@.service` unit; your role only needs to start/enable
`dc@<service>`.

## 2. Register the role in `ansible/docker.yml`

Two edits:
- In `pre_tasks` → `Load healthcheck URLs from Terraform state outputs`, add
  `<service>_backup_healthcheck_url: "{{ terraform_outputs.uptime_backup_<service>_url.value | default('') }}"`.
- In `roles:`, append `- role: <service>` / `tags: <service>,app`.

## 3. Backup folder registration

Append `"<service>"` to `backup_folders` in
`ansible/host_vars/backups/variables.yaml`, then run once (before the first
borgmatic run for this service):

```bash
cd ansible && ansible-playbook -i inventory/hosts backup.yaml
```

(`backup.yaml` targets the `backups` group with `gather_facts: false` +
`ansible.builtin.raw` because the Hetzner Storage Box has a restricted shell —
normal file modules don't work there.)

## 4. Host vars for the backup

Append to `ansible/host_vars/docker/variables.yaml`:

```yaml
<service>_backup_enabled: true
<service>_backup_borgmatic_target: "ssh://{{ backup_storage_box_username }}@{{ backup_storage_box_hostname }}/{{ backup_storage_box_path }}/<service>"
<service>_backup_encryption_passphrase: "{{ backup_passphrase }}"
```

## 5. Secrets

If the service needs its own secret (DB password, admin password, API key),
add it to `secrets.sops.yaml` via `sops secrets.sops.yaml` (never hand-edit
the encrypted blob, never commit plaintext). Remember: a variable loaded via
`community.sops.load_vars` cannot override one already defined elsewhere —
make sure no default under the same name exists in `group_vars`/`host_vars`.

## 6. Pangolin routing

See `.github/instructions/pangolin-route.instructions.md` for
`tofu/pangolin_config/roles.tf` + `tofu/pangolin_config/website_<service>.tf`.
Pay special attention to its two documented pitfalls (missing `hc_hostname`,
target `priority` ordering) — both come from real bugs shipped in this repo.

## 7. Apply and deploy, in this order

Tofu must run first: `docker.yml` reads the Terraform state to populate the
backup healthcheck URL, so the resource needs to exist before the Ansible run.

```bash
cd tofu/pangolin_config && tofu fmt -recursive && tofu validate && tofu plan
tofu apply

cd ../../ansible
ansible-lint
ansible-playbook -i inventory/hosts docker.yml --check --tags <service>,app
ansible-playbook -i inventory/hosts docker.yml --tags <service>,app
```

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
  specific paths need **higher** numbers.
- Compose file is always named `compose.yaml`, never `docker-compose.yml`.
- PUID/PGID (if the image needs them) come from `ansible_facts['user_uid']`/`user_gid'`, not hardcoded.
