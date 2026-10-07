---
applyTo: "ansible/roles/borgmatic/**,ansible/host_vars/**,ansible/roles/*/tasks/main.yml,ansible/roles/*/defaults/main.yml"
description: Non-standard Borgmatic config structure this repo requires, and how to wire up a backup for a service.
---

# Borgmatic backup wiring

**Don't write a borgmatic config by hand.** Every app's config is rendered
by one shared template, `ansible/roles/borgmatic/templates/app.yaml.j2`,
through `ansible/roles/borgmatic/tasks/app.yml`. An app role only declares
*what* to back up; the structure (which deviates from Borgmatic's own
examples in several places) lives in that one template. The interface — the
`borgmatic_app_*` variables — is documented in
`ansible/roles/borgmatic/defaults/main.yml`.

## Structure the shared template guarantees (don't "fix" it)

- `keep_daily` / `keep_weekly` / `keep_monthly` / `keep_yearly` are
  **top-level** — not nested under `retention:`.
- `checks:` (with `name` / `frequency`) is **top-level** — not nested under
  `consistency:`.
- `commands:` with `before: action` / `after: action` + `when: [create]`
  hooks — not `before_backup:` / `after_backup:` / `on_error:`.
- `archive_name_format: '<prefix>-{now:%Y-%m-%dT%H:%M:%S}'` — no
  `{hostname}` prefix. The prefix defaults to the app name with `_` → `-`;
  changing it takes the existing archives out of `prune`'s reach.
- `compression: zstd,10` — not `auto,zstd`.
- `ssh_command: ssh -i /root/.ssh/backup_storage_box_key -p 23` and
  `local_path: /root/.local/bin/borg` (installed by the `borgmatic` role).
- `uptime_kuma:` push block with `states: [start, finish, fail]` when a
  healthcheck URL is given.
- `exclude_patterns` are borg `fm:` patterns anchored at the start of the
  archived path: `'*.log'` works anywhere, but a relative `'cache/*'` matches
  nothing. App-specific excludes must be **absolute paths**.

## 1. Role wiring

In the app role's `tasks/main.yml`, after the compose/env templating:

```yaml
# Borgmatic backup configuration (rôle borgmatic, tasks/app.yml)
- name: Configure borgmatic backup for <Service>
  when: <service>_backup_enabled
  tags: backup
  ansible.builtin.include_role:
    name: borgmatic
    tasks_from: app.yml
    apply:
      tags: backup
  vars:
    borgmatic_app_name: <service>            # /etc/borgmatic.d/<service>.yaml
    borgmatic_app_title: <Service>           # hook messages, task names
    borgmatic_app_target: "{{ <service>_backup_borgmatic_target }}"
    borgmatic_app_passphrase: "{{ <service>_backup_encryption_passphrase }}"
    borgmatic_app_healthcheck_url: "{{ <service>_backup_healthcheck_url }}"
    borgmatic_app_source_directories:
      - "{{ <service>_base_path }}/data"
      - "{{ <service>_base_path }}/compose.yaml"
    # Pick what the app uses — never the live data directory of a database:
    borgmatic_app_postgresql_databases:     # pg_dump runs in the DB container
      - container: <service>_db
        name: <db>
        username: <user>
        password: "{{ <service>_db_password }}"
    borgmatic_app_mysql_databases: []        # same keys (+ dump_command: mariadb-dump
                                             # for the official mariadb image)
    borgmatic_app_sqlite_databases:          # globs, resolved at deploy time
      - "{{ <service>_base_path }}/data/*.db"
    borgmatic_app_exclude_patterns:          # absolute paths only
      - "{{ <service>_base_path }}/data/cache"
```

- **Databases:** PostgreSQL/MySQL are dumped by the client *inside* the DB
  container (`docker exec`), so client and server versions always match.
  MySQL/MariaDB go through `/usr/local/bin/borgmatic-docker-dump`: borgmatic
  2.1 passes the client a `--result-file` on the host, which does not exist
  in the container; the wrapper strips it and writes the client's output there.
  SQLite files matched by the globs (and checked to really be SQLite) are
  copied by a `before` hook with the host's `sqlite3 ".backup"` (online backup
  API: consistent while the app runs, lock held only for the local copy) into
  `/var/lib/borgmatic-sqlite/<app>/`, which borg archives; their live copy
  (`-wal`, `-shm`, `-journal` too) is excluded. Never borgmatic's
  `sqlite_databases`: its streamed `.dump` keeps a read lock until borg has
  sent the whole archive, and an app in rollback-journal mode cannot write
  meanwhile (Pangolin froze entirely on 2026-10-07). A database created after
  the deploy is picked up on the next run of the role, a deleted one fails the
  backup until then. To restore, stop the app, `borgmatic extract` the copy,
  put it back in place and `chown` it to the previous owner.
- Other knobs (`borgmatic_app_archive_prefix`, `borgmatic_app_label`,
  `borgmatic_app_before_commands` / `_after_commands`,
  `borgmatic_app_extra_options`): see the borgmatic role defaults.
- The task also runs `repo-create` with the repo's idempotency idiom
  (borgmatic 2.x prints "Repository already exists. Skipping creation.").

In `defaults/main.yml` of the app role:

```yaml
<service>_backup_enabled: true
<service>_backup_borgmatic_target: "{{ backup_storage_box_url }}/<service>"
<service>_backup_encryption_passphrase: "{{ backup_passphrase }}"
<service>_backup_healthcheck_url: ""
```

`backup_storage_box_url` is a group var (`group_vars/all/variables.yml`).
Nothing goes in `host_vars` unless one host needs to override the target or
passphrase.

## 2. Register the remote folder

Append `"<service>"` to `backup_folders` in
`ansible/host_vars/backups/variables.yaml` (it must match the last path
segment of the target), then run once (creates the directory on the Storage
Box — a normal Ansible run against the app host won't do this for you):

```bash
cd ansible && ansible-playbook -i inventory/hosts backup.yaml
```

`backup.yaml` deliberately uses `gather_facts: false` + `ansible.builtin.raw`
instead of `ansible.builtin.file` — the Storage Box exposes a restricted
shell that breaks normal file modules.

## 3. Optional: healthcheck push URL

If you want backup success/failure pushed to Uptime Kuma, get the push URL
from the `pangolin-route` instructions' `uptimekuma_monitor_push` output,
then wire `<service>_backup_healthcheck_url` into the relevant playbook's
`pre_tasks` → `set_fact` block (see `ansible/docker.yml` for the existing
pattern).

## 4. Molecule

The scenario's `verify.yml` reads `/etc/borgmatic.d/<service>.yaml`; the
shared `verify_app.yml` validates it with the real borgmatic pinned in
`ansible/molecule/_shared/Dockerfile`. `ansible/molecule/trek/` shows how to
seed a SQLite database in `prepare.yml` and assert it is copied by `.backup`.

## Verify

```bash
ansible-playbook -i inventory/hosts <playbook>.yml --check --tags backup
sudo /root/.local/bin/borgmatic config validate --config /etc/borgmatic.d/<service>.yaml
sudo /root/.local/bin/borgmatic --config /etc/borgmatic.d/<service>.yaml create --dry-run
sudo /root/.local/bin/borgmatic --config /etc/borgmatic.d/<service>.yaml list --archive latest
```
