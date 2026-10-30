# Role `papra`

Papra (`papra.sylvain.cloud`, Docker VM) is **on trial** as the replacement of
Paperless-ngx (paused, `docs/runbooks/app-en-pause.md`). Whichever of the two
loses the trial is removed with the `remove-app` skill. App description:
`docs/apps.md`.

- OCR: tesseract.js inside the image. The container runs as the host uid
  (`user:` in `templates/compose.yaml`, as Papra's documentation advises), so
  tesseract.js cannot cache its language models in `/app` and fetches them
  again from `cdn.jsdelivr.net` for every document. Keep the container's
  outbound Internet through `newt` (its only network). If the CDN cannot be
  reached, the document is imported with no text: reprocess it
  (`DOCUMENT_REPROCESSING_ENABLED`, on by default).
- Trash: a deleted document stays 90 days before the nightly purge
  (`papra_deleted_documents_retention_days`, Papra's default is 30); the web
  interface reads the value from the server.
- Task queue (OCR, tagging rules, reprocessing) persisted in
  `app-data/db/tasks.sqlite` (`TASKS_PERSISTENCE_DRIVER=libsql`): with Papra's
  default in-memory queue, a restart (any deploy that changes `.env` or the
  compose) dropped every pending task. The file sits next to `db.sqlite`, so
  the backup's `*.sqlite` glob copies it consistently.
- Sign-up is closed (`papra_registration_enabled: false`): each account is
  made by reopening it for one run (`-e papra_registration_enabled=true`).
- Mobile app: it reaches Papra through the Pangolin SSO wall with a Pangolin
  access token sent as custom headers (`P-Access-Token-Id` /
  `P-Access-Token`, `tofu output -json papra_client_access_tokens` in
  `tofu/pangolin_config`); no path is opened. → `docs/acces-mobile.md`.
  Removing Papra also removes this token (`remove-app` skill, step 6).
