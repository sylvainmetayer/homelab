# Role `kdrive_sync`

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

Part of `nas.yml` (row in `docs/conventions/ansible.md`).

`kdrive_sync` (tag `kdrive_sync`, no dc@: `kdrive-sync.service` oneshot + `.timer` 04:00, a `docker compose run --rm` of `rclone/rclone` through `files/kdrive_sync.py`): one-way nightly `rclone copy` of kDrive over WebDAV (`https://<kdrive_drive_id>.connect.kdrive.infomaniak.com`, SOPS `kdrive_drive_id`/`kdrive_webdav_user`/`kdrive_webdav_app_password`, an Infomaniak app password obscured inside the container) into the UI-created shared folder `/volume1/kdrive` (`miroir/`, run as `sylvain`), never `sync`/`move`/`--delete*` (pinned by its Molecule scenario); a replaced file's previous version goes to `versions/<timestamp>/` (`--backup-dir`), nothing is ever deleted on the NAS; result pushed to `kDrive vers NAS` (`uptime_cron_kdrive_sync_url`); not in borg unless `kdrive_sync_backup_enabled` (`docs/runbooks/kdrive-nas.md`).
