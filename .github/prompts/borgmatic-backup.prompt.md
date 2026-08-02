---
mode: agent
description: Wire up or fix a Borgmatic backup for a service on the docker/pangolin/pi host.
---

Follow `.github/instructions/borgmatic-backup.instructions.md` in full.

Ask the user which service and which host (`docker`, `pangolin`, or `pi`) if
not already given, then base the new `templates/borgmatic-<service>.yaml.j2`
on `ansible/roles/betisier/templates/borgmatic-betisier.yaml.j2` — do not use
a generic Borgmatic example, this repo's structure deviates from upstream
docs in several specific ways (see the instructions file). Wire the
`host_vars` entries, the `backup_folders` registration, and the
`tasks/main.yml` block using the exact repo-create idempotency idiom already
used elsewhere in this repo.

Before finishing, confirm the retention keys and `checks:` are top-level (not
nested under `retention:`/`consistency:`), and that `archive_name_format` has
no `{hostname}` prefix.
