---
mode: agent
description: Wire up or fix a Borgmatic backup for a service on the docker/pangolin/pi host.
---

Follow `.github/instructions/borgmatic-backup.instructions.md` in full.

Ask the user which service and which host (`docker`, `pangolin`, or `pi`) if
not already given, then add the `include_role: borgmatic` /
`tasks_from: app.yml` call to the service role's `tasks/main.yml` — do not
write a borgmatic config template for the service: every config is rendered
by `ansible/roles/borgmatic/templates/app.yaml.j2`, whose structure deviates
from upstream docs in several specific ways (see the instructions file).
Declare the role's `<service>_backup_*` defaults (target derived from
`backup_storage_box_url`) and the `backup_folders` registration.

Before finishing, confirm that no live database directory is in
`borgmatic_app_source_directories` (dump it through
`borgmatic_app_postgresql_databases` / `_mysql_databases` /
`_sqlite_databases` instead), and that any `borgmatic_app_exclude_patterns`
entry is an absolute path.
