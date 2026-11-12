# Role `papra`

Papra (`papra.sylvain.cloud`, Docker VM) is the document app: it replaced
Paperless-ngx (removed in November 2026). App description: `docs/apps.md`.

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

## Backup and restore

The archive holds `app-data/` (originals under
`documents/<original_storage_key>`, as stored in the `documents` table), the
compose, the `.env`, and consistent copies of both databases under
`var/lib/borgmatic-sqlite/papra/` (`opt_apps_papra_app-data_db_db.sqlite`,
`…_tasks.sqlite`; the live files are excluded). Documents are not encrypted
at rest (`file_encryption_key_wrapped` is empty): the files alone are
readable. The copies come out `root:root`: give them back the container's
uid (the host user, `1000:1000` today, `stat -c %u:%g` of the old files).
`db.sqlite` runs in `delete` mode, `tasks.sqlite` in WAL: switch the copy of
the latter back with `sqlite3 tasks.sqlite 'PRAGMA journal_mode=WAL'`.
Drill of 2026-11-02 (864 documents, 795 MB, extract 21 s; integrity `ok`,
counts and a sample of sha256 equal to the live ones) and its commands:
`docs/runbooks/sauvegarde-et-restauration.md`, « Restauration d'essai ».

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
attachment is written. A move that fails after the attachments were written
leaves the message in place for the next run (those attachments would then be
imported twice).

A write error (disk full, NFS gone) leaves that message in place with nothing of
it in the ingestion folder (what it already delivered is taken back, unless Papra
already imported it), retried on the next pass. The following messages are still
processed, and the unit ends failed. An IMAP error still stops the pass. Names
are capped at 120 UTF-8 bytes before the extension, never cutting a character.

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

   and add their two entries to `secrets/secrets-rotation.yaml` in the same commit
   (`papra_intake_imap_user`: `kind: identifier`; `papra_intake_imap_password`:
   `kind: application`, `last_rotated` the day, `estimated: false`,
   `how: docs/runbooks/rotation-des-secrets.md#relève-e-mail-de-papra`): the
   Lint fails on a SOPS key without its entry. That commit is made in the
   `secrets/` submodule and pushed to `homelab-secrets`, then the submodule
   bump (`git add secrets`) goes in the PR (`docs/conventions/secrets.md`).
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
   `ansible/`: a change to `host_vars/` or a bump of `secrets/` alone deploys
   nothing (`deploy-docker-app` only watches `ansible/roles/**` and the host
   playbooks). Test at once:
   `sudo systemctl start papra-intake.service && journalctl -u papra-intake -n 20`.

With `papra_intake_enabled: false` again, the role stops the timer and deletes
the units, the script and the configuration (the folders stay). Before a
`remove-app` of Papra, run that once: the decommission knows nothing of
`/etc/papra-intake.json` and the units.

Follow-up, not wired: an Uptime Kuma push monitor (like
`ntfy-subscribers-check`) to be told when the run keeps failing (expired app
password, IMAP down).

## Connexion par Pocket ID

Client `papra` de `tofu/pangolin_config/pocket_id.tf` (groupe `papra`). Les
`papra_oidc_*` de `defaults/main.yml` lisent les sorties Tofu ; tant qu'elles
manquent, `AUTH_PROVIDERS_CUSTOMS` n'est pas rendu. Fournisseur `pocket-id`
(rappel `/api/auth/oauth2/callback/pocket-id`), PKCE. better-auth lie un compte
existant par e-mail, vérifié **des deux côtés** : better-auth 1.6.11
(`requireLocalEmailVerified`, vrai par défaut, non réglable dans Papra) refuse
un compte Papra dont `users.email_verified` vaut 0, ce qui est le cas de tout
compte créé par inscription. Symptôme : le retour de Pocket ID finit sur
`/api/auth/error`. Remède, par compte, avant sa première connexion par Pocket
ID : `email_verified=1` dans `app-data/db/db.sqlite` (commande dans
`docs/runbooks/pocket-id.md`, copie de la base avant). L'inscription fermée
empêche d'en créer un. Le mot de passe et les clés d'API restent (secours,
appli mobile).

## Remplissage par l'IA (`papra-enrich.timer`)

Le module IA de Papra reste **coupé** (`AI_IS_ENABLED` n'est plus rendu, faux
par défaut) : il ne sait que les tags, n'exclut rien et envoie tout document
(étude du 2026-11-10). À sa place, `files/papra_enrich.py` (Python stdlib),
lancé toutes les heures (`papra_enrich_schedule`) sous le compte du conteneur,
remplit le **Montant** (total TTC à payer, frais compris), la **Fin de
validité** (fin de garantie, de contrat ou expiration écrite, jamais une
échéance de paiement ni une date d'émission) et des **tags existants**, par la
passerelle IA de Pangolin (`https://ia.sylvain.cloud/v1`, format OpenAI, clé
virtuelle `papra` lue dans le state, `papra_ai_model`). Il parle à Papra par
l'IP du conteneur sur le réseau `newt` (`docker inspect`, groupe `docker` de
l'unité) : aucun port publié, et l'URL publique passe par le mur SSO.

Un document part au modèle seulement s'il porte **au moins un tag**, **aucun**
de `papra_enrich_excluded_tags` (`Sante`, `Identite`, `Banque-Finances`,
`Impots`, `Travail-RH`), pas la marque `papra_enrich_done_tag` (`IA-faite`),
s'il a été importé il y a plus de 24 h et s'il a du texte. Le texte part
tronqué à `papra_enrich_max_chars` (12 000) ; au-delà de
`papra_enrich_skip_chars` (100 000), le document est sauté. Un tag exclu ou la
marque **introuvable** dans Papra arrête le passage avant tout envoi : c'est la
garde des pièces d'identité, tant que `Identite` n'existe pas, rien ne part.

Seuls les champs vides sont remplis, jamais une valeur saisie ; les tags sont
pris dans la liste existante, hors exclus, jamais créés. La marque est posée
avant les champs, un document sans réponse utile compris : jamais renvoyé au
modèle, même si Papra refuse ensuite une écriture (journalisé, le passage
continue). Les plus
anciens d'abord, `papra_enrich_batch_size` (20) documents par passage :
l'arriéré (~400) en une vingtaine d'heures, puis les nouveaux au fil de l'eau.
Un document sans texte ou trop long n'est pas marqué (un OCR refait le
reprendra) et ne compte pas dans le lot. Une erreur de la passerelle, un 429
ou un 5xx arrête le passage, sans nouvel essai : le suivant reprend.

Journal (`journalctl -u papra-enrich`) : une ligne par document, son
identifiant, les champs remplis, le nombre de tags ajoutés et les tokens ;
jamais le nom ni le contenu. Budget : clé `papra` à 5 M tokens à vie
(`tofu/pangolin_config/ai_gateway.tf`), ~3 650 tokens par document (mesure du
2026-11-10). Les textes envoyés partent chez Anthropic ; le journal des appels
de la passerelle les garde 90 jours, en clair, dans la base de Pangolin
(`docs/runbooks/passerelle-ia.md`).

Rendu seulement si la clé SOPS `papra_enrich_api_key` (une clé d'API Papra,
lue telle quelle) **et** la clé de la passerelle existent ; sinon le passage
retire script, unités et `/etc/papra-enrich.json` (`0600`, `diff: false`). La
copie d'exercice n'a pas de state (`terraform_outputs = {}`) : jamais installé.

### Mise en route

1. Dans Papra, créer les tags `Identite` (avec sa règle de classement) et
   `IA-faite`. Vérifier que `Sante`, `Banque-Finances`, `Impots`, `Travail-RH`
   et les propriétés `Montant` (nombre) et `Fin de validité` (date) existent.
2. Paramètres > Clés d'API : une clé avec `documents:read`,
   `documents:update`, `tags:read`, `custom-properties:read`, rien d'autre.
3. La poser sans écho, depuis la racine d'une branche :

   ```bash
   read -rs valeur
   printf '%s' "$valeur" | python3 -Ic 'import json, sys; print(json.dumps(sys.stdin.read()))' \
     | sops set --value-stdin secrets/ansible.sops.yaml '["papra_enrich_api_key"]'
   unset valeur
   ```

   avec son entrée de `secrets/secrets-rotation.yaml` dans le même commit du
   sous-module, puis le bump de `secrets/` en PR.
4. Après le merge : `ansible-playbook docker.yml --tags papra` depuis
   `ansible/` (un bump de `secrets/` seul ne déploie rien).
5. Premier essai à blanc, 5 documents, dans un terminal (le modèle est
   appelé, rien n'est écrit, les valeurs proposées s'affichent), en SSH
   sous `sylvain` (propriétaire de la configuration, membre de `docker`) :
   `python3 -I /usr/local/libexec/papra_enrich.py --config /etc/papra-enrich.json --dry-run --limit 5`.
   Puis `sudo systemctl start papra-enrich.service` et
   `journalctl -u papra-enrich -n 30` pour un vrai passage.
