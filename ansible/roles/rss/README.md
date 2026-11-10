# Role `rss`

FreshRSS (`rss`, Docker VM), read in the browser only: API off except for
Homepage's widget, Karakeep Button extension (comments in `defaults/main.yml`
and `tasks/main.yml`). App description: `docs/apps.md`.

## Capabilities

`cap_drop: ALL` plus six capabilities, tested on the pinned image (1.30.4) with
fictitious data owned as in production (`data` root:www-data,
`data/users/<user>` `0770` www-data, `extensions` root:www-data `0750`), rootful
and rootless, removing each in turn (PR #1172):

| Capability | Without it |
|---|---|
| `CHOWN` | entrypoint warnings: `chown -R :www-data` refused on www-data's files |
| `DAC_OVERRIDE` | same `chown` and `chmod`: cannot enter `data/users/<user>` (`0770` www-data) |
| `FOWNER` | entrypoint warnings: `chmod -R g+rX,g+w` refused on www-data's files |
| `KILL` | `AH00046`: Apache cannot signal its workers, a stop takes ~11 s |
| `SETGID` | **no error at start, workers stay root**; `su` of the cron fails |
| `SETUID` | Apache exits (`AH02162`) |

The first three only log warnings, but leave the permissions of a restored or
hand-edited file unrepaired. All six are in Docker's default set; `DAC_READ_SEARCH`
would also cross these folders but opens a path to the host's files
(`docs/conventions/container-hardening.md`). Workers and the cron's PHP keep no
capability. `NET_BIND_SERVICE` is not needed on port 80: Docker sets
`ip_unprivileged_port_start=0` on a bridge network (read at 0 in the running
container); under `network_mode: host` it would be.

## Disk writes

FreshRSS was the Docker VM's top disk writer (~24 GB in 68 h, 2026-11-01,
`docs/conventions/resource-limits.md` « Disk I/O »): one SQLite database per
user (`data/users/<user>/db.sqlite`, ~330 MB, 846 feeds), in rollback-journal
mode with `synchronous=FULL`. The role sets three things:

- **Refresh delay** `rss_ttl_default` (3 h; FreshRSS's default is 1 h): the
  `ttl_default` key of each `data/users/<user>/config.php`, set by `replace`
  as the role does for `api_enabled` (inserted when the file has none). A UI
  change of the default (Configuration > Archivage) is undone by the next
  deploy; a feed with its own TTL (Configuration > Flux) keeps it, at most
  once an hour. With the hourly cron, a feed is skipped while
  `now <= lastUpdate + TTL` (no margin) and its last update ended seconds
  after the previous run started: 3 h exactly refreshes each feed every
  **4 h** (a TTL just under 3 h, e.g. 10500, for a real 3 h).
- **Cron hourly** (`CRON_MIN=17` in the compose): FreshRSS 1.30 compares a
  feed's TTL with its last *successful* update (`feedController.php`,
  `actualizeFeeds`), so a feed in error is retried, and its `error` column
  written, at every cron run whatever its TTL. Every 15 min that was 166 feeds
  in error × 4 per hour. The cleanup of those feeds is Sylvain's (UI), not the
  role's.
- **WAL**: each `db.sqlite` is switched once with
  `PRAGMA journal_mode=WAL`, kept in the file header (FreshRSS sets no journal
  mode of its own). A commit then appends to `db.sqlite-wal` instead of
  creating, fsyncing and deleting a `-journal` file, and readers (the web UI)
  no longer block the refresh. Trade-offs: two more files next to the
  database (`-wal`, `-shm`, owned by www-data; the `-wal` grows up to
  ~4 MB between checkpoints, more during a long read), all on one host only
  (no NFS); a copy of `db.sqlite` alone, without its `-wal`, may miss the last
  commits. Backups are unaffected: the borgmatic template copies a WAL database
  with `VACUUM INTO` (one read transaction, never blocking FreshRSS) and
  excludes the live `db.sqlite`, `-wal`, `-shm` and `-journal`
  (`ansible/roles/borgmatic/README.md`); `.backup`, its fallback for a
  rollback-journal database, starts over at each write of FreshRSS. To go back:
  `sqlite3 db.sqlite 'PRAGMA journal_mode=DELETE'`, app stopped, and drop the
  WAL tasks.

Measure the container's writes (two reads ~15 min apart, a full cron cycle,
outside borgmatic's 00:30-03:00 window; from `ansible/`):

```bash
mise exec -- ansible docker -o -m shell -a 'id=$(docker ps -q --no-trunc -f name=^rss$); date +%s; grep "^254:0" /sys/fs/cgroup/system.slice/docker-$id.scope/io.stat'
```

The write rate is the `wbytes` (and `wios`) difference over the `date`
difference. Before this change (2026-11-02 07:32-07:4x): see the PR.

## Connexion par Pocket ID

Client `rss` de `tofu/pangolin_config/pocket_id.tf` (groupe `rss`, le foyer).
Quand les sorties Tofu sont là, le compose active le `mod_auth_openidc` de
l'image officielle (`OIDC_*`, rappel `/i/oidc/`, en-têtes `X-Forwarded-*` de
Traefik), puis le rôle passe `auth_type` de `form` à `http_auth` dans
`freshrss_data/config.php`, après le redémarrage (jamais `http_auth` sans
OIDC devant). **Plus de formulaire de mot de passe sur le web** : le
`preferred_username` Pocket ID est le compte FreshRSS, identique au caractère
près (`sylvain` des deux côtés, vérifié le 2026-11-06) ; un membre du groupe
sans compte en reçoit un neuf (`http_auth_auto_register`). Seul `/i/` passe par
l'OIDC : l'API (Google Reader, Fever, mots de passe d'API, Homepage) n'est pas
touchée. Le moniteur d'Uptime Kuma sonde `/api/` (`website_rss.tf`). Pas de
PKCE (l'Apache de l'image n'en règle pas).

Installation : le compose porte `FRESHRSS_INSTALL` / `FRESHRSS_USER`
(`rss_default_user`, `sylvain`), pour qu'un dossier vide (reconstruction,
exercice) ait sa base `users/<compte>/db.sqlite` dès le premier démarrage ;
déjà installé, rien ne change. Ce compte neuf n'a ni mot de passe ni flux :
sans l'archive Borg, le secours par le formulaire ci-dessous demande d'abord
`cli/update-user.php --user <compte> --password ...` dans le conteneur.

Secours (Pocket ID en panne, ou mauvais nom d'utilisateur) : sur l'hôte docker,
`sed -i "s/'auth_type' => 'http_auth',/'auth_type' => 'form',/"
/opt/apps/rss/freshrss_data/config.php` rend le formulaire tout de suite
(FreshRSS relit le fichier à chaque requête) ; mais mod_auth_openidc garde
`/i/` tant que le compose a `OIDC_ENABLED`, il faut donc aussi retirer les
lignes `OIDC_*` du compose et relancer `dc@rss`. Le prochain passage du rôle
remet l'OIDC si les sorties Tofu existent toujours.
