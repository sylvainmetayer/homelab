# yamtrack

[Yamtrack](https://github.com/FuzzyGrim/Yamtrack) (AGPL-3.0, 0.26.3, publiée
le 2026-08-23) sur **https://yamtrack.sylvain.cloud** : suivi de films, séries
(saison par saison), animés, mangas, jeux, livres, comics et jeux de société.
VM docker, `dc@yamtrack`, deux conteneurs : `yamtrack` (nginx, gunicorn et
celery sous supervisord, sur `newt` et sur le réseau interne `yamtrack`) et
`yamtrack-redis` (réseau interne seulement). Derrière le SSO de Pangolin (rôle
`yamtrack`, sans membre : administrateurs Pangolin seulement), puis le compte
propre à Yamtrack. Amont actif (dernier envoi le jour de l'ajout).

## Premier compte

L'inscription est fermée (`REGISTRATION=False`, `yamtrack_registration_enabled:
false`). Pour créer un compte (le premier, puis chaque suivant) :

1. `ansible-playbook docker.yml --tags yamtrack -e yamtrack_registration_enabled=true`
2. « Register » sur `https://yamtrack.sylvain.cloud` (derrière le SSO).
3. Le même passage sans le `-e`, qui referme l'inscription.

Tant qu'aucun compte n'existe, la table `users_user` est vide et le test de
restauration (`.github/restore-test/apps.json`) échoue à la première nuit : le
faire avant. De même la copie SQLite n'existe qu'après le premier démarrage
(migrations) : elle entre dans la configuration borgmatic au passage suivant du
rôle, et le test échoue « aucun dump ni copie sqlite » d'ici là.

Pas de clé SOPS : `SECRET` (clé Django) est dérivé de `backup_passphrase`
(`-yamtrack-secret`), l'image en a une par défaut, publique. Les clés des
sources de métadonnées (TMDB, MyAnimeList, IGDB, Hardcover, ComicVine) sont
celles que l'image fournit par défaut, partagées : elles ont des limites de
débit basses (IGDB surtout). Aucune n'est posée ici ; en cas de refus, créer sa
clé chez la source et l'ajouter comme clé SOPS lue par `env.j2`.

## Connexion à Jellyfin (facultative, non faite)

Yamtrack peut marquer comme vu ce que Jellyfin lit, par le plugin Webhook de
Jellyfin (catalogue « Jellyfin Stable »; Jellyfin avec TMDB et TVDB comme
sources de métadonnées) : une destination générique qui poste sur
`https://yamtrack.sylvain.cloud/webhook/jellyfin/<jeton>` à chaque début et fin
de lecture, `<jeton>` étant celui du compte, affiché dans les réglages
d'intégrations de Yamtrack (modèle JSON donné par la même page). **Elle n'est
pas configurée** et ne marche pas en l'état : le POST vient du serveur Jellyfin
(le NAS), sans session, et se heurterait au SSO de Pangolin comme à la règle
pays. L'ouvrir demande une exception de chemin ciblée
(`/webhook/jellyfin/*` dans `local.path_bypasses`, `rules.tf`, avec une entrée
de `path_bypass_images.json`), à décider à part : le jeton dans l'URL serait
alors la seule barrière du chemin. L'import ponctuel depuis Trakt, Simkl,
MyAnimeList, AniList ou Kitsu et l'export CSV ne demandent rien de tel.

## Sauvegarde

Borgmatic par le modèle partagé : `db/` (la base SQLite `db.sqlite3` est
copiée par `sqlite3 .backup` dans le dossier de staging archivé, sa copie
vivante exclue de l'archive ; jamais le `sqlite_databases` de borgmatic),
`compose.yaml` et `.env` (`SECRET`). Redis n'est qu'un cache et la file de
Celery : sans volume, hors sauvegarde. Moniteur « Backup Yamtrack », test de
restauration (table `users_user`).

## Durcissement

L'image démarre en root : son entrypoint lance les migrations, remappe son
compte `abc` sur `PUID`/`PGID` (ceux de l'utilisateur de déploiement, dans le
`.env`), fait un `chown` de `db/` et supervisord lance gunicorn et celery sous
`abc`. Pas de `user:` ni de lecture seule (l'entrypoint réécrit `/etc/passwd`
et `/etc/group`) ; en revanche `cap_drop: ALL` avec six capacités rendues,
essayées en local sous podman et suffisantes : `CHOWN` et `FOWNER` (chown de
`db/`), `DAC_OVERRIDE`, `SETUID` et `SETGID` (usermod, supervisord), `KILL`
(supervisord arrête gunicorn et celery). `no-new-privileges` partout. Essayé en
local (podman, mêmes options, Redis 8.2) : migrations passées, `GET /health/`
(base, cache, Redis, ping Celery) répond 200, la page de connexion 200,
processus gunicorn, celery et nginx sous `abc`.

Le premier démarrage applique de nombreuses migrations (plus d'une minute en local, sur
un disque rapide) : `start_period: 180s` au healthcheck, à surveiller au
premier déploiement sur le disque de la VM.

`mem_limit` : 1g pour l'appli (~370 Mio mesurés en local après les migrations,
un worker celery par cœur, la VM en a 3) et 128m pour Redis (~24 Mio). Valeurs
prudentes, **à remesurer** (`memory.peak`, rapport `mem_report`).

## Non vérifié

Le déploiement réel, une inscription et un parcours dans un navigateur, le
comportement derrière Pangolin (`URLS` règle CSRF et `ALLOWED_HOSTS`), la copie
SQLite par borgmatic sur le Storage Box, l'écriture de la base par `abc`
(uid de l'hôte) sur le bind mount `db/` de la VM (essayé seulement en espace
de noms utilisateur de podman).
