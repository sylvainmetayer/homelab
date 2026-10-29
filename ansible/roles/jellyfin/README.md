# Role `jellyfin`

Moved from `AGENTS.md` (agent-facing notes, kept in English); the index there links here.

Part of `nas.yml` (row in `docs/conventions/ansible.md`): `dc@jellyfin`, media from the UGOS shared folder `media` mounted `:ro`; the role asserts the share and its library folders before writing anything, under its own tag only. TLS in front: `ansible/roles/nas_proxy/README.md`.

Jellyfin itself sits on its project's `media` network only (`jellyfin_media` for Docker, fixed subnet, created by `dc@jellyfin` and joined as external by `nas_proxy`, hence `nas_proxy` after `jellyfin`; Traefik at `172.30.96.10`, the IP set in Jellyfin's "Known proxies") and keeps `8096` published on the LAN as a fallback.

Backup (tag `backup`, `jellyfin_backup_enabled`, default true): `config/` and the compose through the shared borgmatic template, run by the NAS's containerised borgmatic (02:30, `ansible/roles/borgmatic/README.md`); the SQLite databases `config/data/*.db` are copied by `sqlite3 .backup`, their live copy excluded. Push monitor « Backup Jellyfin » (`tofu/pangolin_config/backup_jellyfin.tf`, outside `local.websites`: Jellyfin is no public resource), restore-tested (`.github/restore-test/apps.json`). The media are not in borg.
