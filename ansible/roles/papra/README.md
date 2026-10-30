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
  compose) dropped every pending task. Only `pending` jobs survive a restart:
  the job running at that moment stays `processing` for good (the
  `@cadence-mq/driver-libsql` worker only picks `pending` ones and recovers
  none), so its document is left with no text: reprocess it. Finished jobs
  are never deleted (Papra 26.7 does not set `deleteJobOnCompletion`), so the
  file only grows, by a small row per job. The driver puts it in WAL mode; it
  sits next to `db.sqlite`, so the backup's `*.sqlite` glob copies it consistently
  — from the deploy *after* the one that created it: the glob is resolved
  before Papra's restart handler. After the deploy that turns it on, run
  `ansible-playbook docker.yml --tags backup` once.
- Sign-up is closed (`papra_registration_enabled: false`): each account is
  made by reopening it for one run (`-e papra_registration_enabled=true`).
- Mobile app: it reaches Papra through the Pangolin SSO wall with a Pangolin
  access token sent as custom headers (`P-Access-Token-Id` /
  `P-Access-Token`, `tofu output -json papra_client_access_tokens` in
  `tofu/pangolin_config`); no path is opened. → `docs/acces-mobile.md`.
  Removing Papra also removes this token (`remove-app` skill, step 6).

## Mail intake (`papra_intake_*`, off by default)

A mail sent to a dedicated Infomaniak address ends up in Papra, with no
third-party relay: `papra-intake.timer` (every 15 min, `papra_intake_schedule`)
runs `files/papra_intake.py` (Python stdlib) as the container's user. It reads
`papra_intake_imap_folder` (`INBOX`) of `mail.infomaniak.com:993` over IMAPS
(certificate verified) and, per message:

- **sender allowed** (`papra_intake_allowed_senders`: exact address, or a
  domain written `@example.fr`): every attachment whose extension is in
  `papra_intake_extensions` (PDF, images, office documents, text) and whose
  size is at most `papra_max_upload_size` (25 MB) is written to
  `ingestion/<papra_intake_organization_id>/`, which Papra imports then empties.
  The message then moves to `papra_intake_done_folder` (`Papra/Importé`).
  Names are made safe (base name only, no leading dot, `[\w.- ]`), never
  overwrite (`-1`, `-2`… suffix): each file is written to `intake-tmp/` first
  then hard-linked into the watched folder, so Papra never sees a partial
  file. A small inline image referenced by `Content-ID` (signature logo) is
  dropped.
- **the mail itself, on demand**: forward the mail (or write one) to the
  intake address and type `[mail]` at the start of the subject
  (`papra_intake_body_marker`, case-insensitive; the `Fwd:`, `Fw:`, `TR:`,
  `RE:` a forward or reply puts before it are skipped, so `TR: [mail] Avis`
  matches but `TR: Avis [mail]` does not). On top of its attachments
  (unchanged), the run then writes `<YYYY-MM-DD> - <subject>.txt` (the
  `Date` header's day, subject without prefixes nor marker): `De :`, `À :`,
  `Date :`, `Objet :` lines then the body as text (the `text/plain` part, else
  the HTML one stripped of its tags), for Papra's search and tagging rules;
  and `<same name>.eml`, the original message byte for byte, as proof. Both
  bypass `papra_intake_extensions`, take the same safe names and `-1`
  suffixes, and are each dropped over `papra_max_upload_size` (an `.eml`
  carrying large attachments then goes, the `.txt` stays; the journal says
  so). A forwarded mail's `De :` is the forwarder: the original sender is in
  the body. An empty marker turns this off.
- **any other sender**: the message moves, untouched, to
  `papra_intake_rejected_folder` (`Papra/Refusé`); the journal keeps its UID
  and the sender's domain only. So does a message over 4× the size cap.

Nothing is ever deleted from the mailbox (IMAP `MOVE`, or `COPY` + `\Deleted`
+ `UID EXPUNGE` of that UID alone); both folders are created when missing,
and a folder that can be neither created nor found stops the run before any
attachment is written. A write error, or a move that fails after the
attachments were written, leaves the message in place for the next run
(attachments already written by that run would then be imported twice).

The `From` header can be forged: the allow-list stops strays and spam, not a
targeted sender. Keep the intake address to yourself.

Credentials: the SOPS keys `papra_intake_imap_user` (the address, an
identifier) and `papra_intake_imap_password` (an Infomaniak *application
password*, not the account password). They land in `/etc/papra-intake.json`
(`0600`, owned by the unit's user, `diff: false`), never on a command line.
Logs: `journalctl -u papra-intake`.

### Enabling it

1. In the Infomaniak Manager, create the intake address and an application
   password for it (Service Mail > the address > Application passwords).
   Prefer a dedicated address: the password opens the whole mailbox. A
   sub-address (`sylvain+papra@…`) works too, with the main mailbox's login
   and `papra_intake_imap_folder` set to the folder a filter files those
   mails in, but the host then holds a key to all of that mailbox.
2. Store both, without echo, from the repo root of a branch:

   ```bash
   read -r valeur   # the IMAP login (the address)
   printf '%s' "$valeur" | python3 -Ic 'import json, sys; print(json.dumps(sys.stdin.read()))' \
     | sops set --value-stdin secrets/ansible.sops.yaml '["papra_intake_imap_user"]'
   read -rs valeur  # the application password (no echo)
   printf '%s' "$valeur" | python3 -Ic 'import json, sys; print(json.dumps(sys.stdin.read()))' \
     | sops set --value-stdin secrets/ansible.sops.yaml '["papra_intake_imap_password"]'
   unset valeur
   ```

   and add their two entries to `secrets-rotation.yaml` in the same commit
   (`papra_intake_imap_user`: `kind: identifier`; `papra_intake_imap_password`:
   `kind: application`, `last_rotated` the day, `estimated: false`,
   `how: docs/runbooks/rotation-des-secrets.md#relève-e-mail-de-papra`): the
   Lint fails on a SOPS key without its entry.
3. In `ansible/host_vars/docker/variables.yaml`:

   ```yaml
   papra_intake_enabled: true
   papra_intake_allowed_senders:
     - sylvain@example.fr
     - "@scanner-domain.example"
   ```

   (`papra_intake_organization_id` if the target organization is not
   `org_z9tq7wl3o5airawxel6f3e5i`.)
4. After the merge, run `ansible-playbook docker.yml --tags papra` from
   `ansible/`: a change to `host_vars/` or `secrets.sops.yaml` alone deploys
   nothing (`deploy-docker-app` only watches `ansible/roles/**` and the host
   playbooks). Test at once:
   `sudo systemctl start papra-intake.service && journalctl -u papra-intake -n 20`.

With `papra_intake_enabled: false` again, the role stops the timer and deletes
the units, the script and the configuration (the folders stay). If Papra loses
its trial, run that once before `remove-app`: the decommission knows nothing of
`/etc/papra-intake.json` and the units.

Follow-up, not wired: an Uptime Kuma push monitor (like
`ntfy-subscribers-check`) to be told when the run keeps failing (expired app
password, IMAP down).
