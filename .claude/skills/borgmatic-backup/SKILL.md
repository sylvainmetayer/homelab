---
name: borgmatic-backup
description: Wire up or fix a Borgmatic backup for a service on the docker/pangolin/pi host, targeting the Hetzner Storage Box. Use when adding backup coverage to an existing service, or when a borgmatic config needs to match this repo's required (non-standard) structure.
---

# Borgmatic backup wiring

**Don't write a borgmatic config from generic Borgmatic docs.** This repo
requires a specific structure that deviates from Borgmatic's own examples in
several places. Always copy
`ansible/roles/betisier/templates/borgmatic-betisier.yaml.j2` as your
starting point.

## Required structure (deviations from generic Borgmatic configs)

- `keep_daily` / `keep_weekly` / `keep_monthly` / `keep_yearly` are
  **top-level** — not nested under `retention:`.
- `checks:` (with `name` / `frequency`) is **top-level** — not nested under
  `consistency:`.
- Use `commands:` with `before: action` / `after: action` + `when: [create]`
  hooks — not `before_backup:` / `after_backup:` / `on_error:`.
- `archive_name_format: '<service>-{now:%Y-%m-%dT%H:%M:%S}'` — no
  `{hostname}` prefix.
- `compression: zstd,10` — not `auto,zstd`.
- `ssh_command: ssh -i /root/.ssh/backup_storage_box_key -p 23` — the Storage
  Box uses a non-standard port and a dedicated key, not the default SSH
  config.
- `local_path: /root/.local/bin/borg` (borgmatic/borg are installed to the
  root user's local bin by the `borgmatic` role, not system-wide).
- Optional `uptime_kuma:` push block, guarded by
  `{% if <service>_backup_healthcheck_url is defined and <service>_backup_healthcheck_url %}`,
  with `states: [start, finish, fail]`.
- If the service has a MySQL/MariaDB database, add a top-level
  `mysql_databases:` block (`container`, `port`, `name`, `username`,
  `password`) rather than relying on filesystem backup of the DB volume.

## 1. Template + role wiring

- Create `templates/borgmatic-<service>.yaml.j2` in the service's role,
  copied from the betisier reference and adapted (source_directories, DB
  block if any, target path, passphrase).
- In `defaults/main.yml`: `<service>_backup_enabled: true`, plus empty
  placeholders for target/passphrase (real values live in `host_vars`).
- In `tasks/main.yml`, add a block guarded by `when: <service>_backup_enabled`,
  tagged `backup`:
  1. Template `borgmatic-<service>.yaml.j2` → `{{ borgmatic_config_dir }}/<service>.yaml`, owner/group `root`, mode `0600`.
  2. Initialize the repo with the exact idempotency idiom used everywhere
     else in this repo (copy verbatim, don't rewrite it):
     ```yaml
     - name: Initialize borg repository for <Service>
       become: true
       ansible.builtin.command:
         cmd: >-
           /root/.local/bin/borgmatic
           --config {{ borgmatic_config_dir }}/<service>.yaml
           repo-create --encryption {{ borgmatic_encryption_mode | default('repokey-blake2') }}
       register: <service>_borg_repo_create
       changed_when: "'repository already exists' not in <service>_borg_repo_create.stderr"
       failed_when: >
         <service>_borg_repo_create.rc != 0 and
         'repository already exists' not in <service>_borg_repo_create.stderr
     ```

## 2. Host vars

Append to `ansible/host_vars/<host>/variables.yaml` (`docker`, `pangolin`, or
`pi` — match where the service actually runs):

```yaml
<service>_backup_enabled: true
<service>_backup_borgmatic_target: "ssh://{{ backup_storage_box_username }}@{{ backup_storage_box_hostname }}/{{ backup_storage_box_path }}/<service>"
<service>_backup_encryption_passphrase: "{{ backup_passphrase }}"
```

## 3. Register the remote folder

Append `"<service>"` to `backup_folders` in
`ansible/host_vars/backups/variables.yaml`, then run once (creates the
directory on the Storage Box — a normal Ansible run against the app host
won't do this for you):

```bash
cd ansible && ansible-playbook -i inventory/hosts backup.yaml
```

`backup.yaml` deliberately uses `gather_facts: false` + `ansible.builtin.raw`
instead of `ansible.builtin.file` — the Storage Box exposes a restricted
shell that breaks normal file modules.

## 4. Optional: healthcheck push URL

If you want backup success/failure pushed to Uptime Kuma, get the push URL
from the `pangolin-route` skill's `uptimekuma_monitor_push` output, then wire
`<service>_backup_healthcheck_url` into the relevant playbook's
`pre_tasks` → `set_fact` block (see `ansible/docker.yml` for the existing
pattern) so it reaches the `{% if %}` guard in the template.

## Verify

```bash
ansible-playbook -i inventory/hosts <playbook>.yml --check --tags backup
sudo borgmatic --config /etc/borgmatic.d/<service>.yaml --list
sudo borgmatic --config /etc/borgmatic.d/<service>.yaml create --dry-run
```
