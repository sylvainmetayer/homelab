# jellystat

[Jellystat](https://github.com/CyferShepard/Jellystat) (MIT, 1.1.12, publiée
le 2026-09-08) sur **https://jellystat.sylvain.cloud** : statistiques de
Jellyfin (historique de lecture, plus regardés, par utilisateur et appareil).
VM docker, `dc@jellystat`, deux conteneurs : `jellystat` (sur `newt` et sur le
réseau interne `jellystat`) et `jellystat-db` (PostgreSQL 18, réseau interne
seulement), derrière le SSO de Pangolin (rôle `jellystat`, sans membre direct :
l'accès vient du groupe Pocket ID `jellystat`), puis le compte propre à Jellystat.

## Où il tourne, et pourquoi

Jellyfin est sur le NAS, **privé** (`media.sylvain.cloud` par le Traefik du NAS
et le client Pangolin) et déployé à la main (`nas.yml`). Deux choix possibles :

- **VM docker (retenu).** La VM joint déjà Jellyfin sur le LAN :
  `http://192.168.1.137:8096`, le port que Jellyfin publie en secours, celui
  que le widget de Homepage utilise (`homepage_jellyfin_url`) et que sa
  sonde interroge. Jellystat y bénéficie du modèle de tout le reste : route
  Pangolin déclarée dans Tofu, SSO, sauvegarde borgmatic de la VM
  (`borgmatic` depuis la VM, pas depuis le conteneur du NAS), déploiement par
  la CI. Le trafic Jellystat vers Jellyfin ne sort pas du LAN.
- NAS : il faudrait un rôle de plus dans `nas.yml` (à la main), un routeur et un
  nom privés dans `nas_proxy` (DNS, certificat, ressource privée Pangolin),
  et PostgreSQL demanderait un dump par l'hôte avant borgmatic (le borgmatic
  du NAS n'a pas de `docker exec`, voir le drop-in de `mediamanager`). Écarté.

Contrepartie : si le NAS est éteint ou si le port 8096 n'est plus publié,
Jellystat n'a plus de données fraîches (il garde l'historique). Si ce port
disparaît un jour, changer `jellystat_jellyfin_url`.

## Clé d'API Jellyfin (SOPS) : le service n'existe qu'avec elle

Clé SOPS `jellystat_jellyfin_api_key` (`secrets/ansible.sops.yaml`), créée dans
Jellyfin (Tableau de bord → Avancé → Clés API, nom `jellystat`). Une clé
Jellyfin n'a pas de périmètre : elle vaut un administrateur (Jellystat lit
bibliothèque, utilisateurs, sessions). Elle est écrite dans le `.env` (`0600`)
comme `JF_API_KEY`, avec `JF_HOST` ; ces deux variables l'emportent sur ce que
l'assistant de Jellystat enregistre en base (`backend/classes/config.js`).

Sans la clé, le rôle affiche un avertissement et **ne rend ni compose, ni
`.env`, ni sauvegarde, ni ne démarre** quoi que ce soit (jamais de défaut :
la variable est lue avec `default('')`, et son nom reste celui de la clé SOPS,
qu'aucun rôle ne définit : règle de précédence, `docs/conventions/secrets.md`).
Une installation déjà déployée dont on retirerait la clé reste telle quelle :
le rôle ne l'arrête pas.

## Premier lancement

1. Créer la clé et la poser (`sops set`), `ansible-playbook docker.yml --tags
   jellystat`, après `tofu apply` de `pangolin_config` (route, moniteurs, URL
   de la sauvegarde).
2. Ouvrir `https://jellystat.sylvain.cloud` (SSO), l'assistant demande de créer
   le compte de Jellystat (identifiant et mot de passe de Sylvain, dans le
   gestionnaire de mots de passe) puis les paramètres de Jellyfin : l'URL et la
   clé du `.env` sont déjà celles utilisées, quoi que l'écran montre.
3. Lancer une synchronisation (Paramètres → Tâches).

Tant que l'assistant n'a pas été fait, la table `app_config` est vide et le
test de restauration (`.github/restore-test/apps.json`, table `app_config`)
échoue à la première nuit : le faire avant.

## Ce qui est secret, et d'où il vient

| Valeur | Origine |
|---|---|
| Mot de passe PostgreSQL | dérivé de `app_secrets_seed` (`backup_passphrase` par défaut ; `-jellystat-db`), comme HealthLog |
| `JWT_SECRET` | dérivé de `app_secrets_seed` (`-jellystat-jwt`) ; le changer ne fait que déconnecter |
| Clé d'API de Jellyfin | SOPS `jellystat_jellyfin_api_key` |
| Compte de Jellystat | base (assistant) ; pas de variable `JS_USER`/`JS_PASSWORD` (compte de secours de l'amont, non posé) |

## Sauvegarde

Borgmatic par le modèle partagé : dump `pg_dump` de la base `jellystat` (via
`docker exec` dans `jellystat-db`), `compose.yaml` et `.env`. Pas le volume de
la base (copié à chaud) ni `backup-data/` (sauvegardes JSON que Jellystat
prend à la demande). Moniteur « Backup Jellystat », test de restauration.

## Données PostgreSQL : dossier `postgresql/`, ancien volume gardé

Depuis le 12/11/2026 la base vit dans `/opt/apps/jellystat/postgresql/` (bind mount sur
`/var/lib/postgresql`, même point de montage qu'avant : PostgreSQL 18 range ses
fichiers sous `18/docker`), et non plus dans le volume nommé
`jellystat_postgres_data`. Raison : auditd surveille `/var/lib/docker` en récursif,
chaque ouverture de fichier de la base y était enregistrée (README du rôle
`security`). Dossier à `70:70` en `0700` (uid de `postgres` dans l'image
alpine), créé par Ansible avant le premier démarrage. Pas dans borg : le dump
reste la sauvegarde (le test de restauration et le mode `drill_mode` ne
touchent que le dump, rien n'y change).

**Migration au déploiement** (`tasks/migrate_postgres_volume.yml`) : seulement
si le volume nommé existe et contient des données, et que `postgresql/` est
absent ou vide. `dc@jellystat` est arrêté (appli et base, `compose stop` puis
contrôle qu'aucun conteneur du projet ne tourne), le volume est copié avec
`cp -a` dans `postgresql.migrating/`, comparé (même nombre d'entrées, un
`PG_VERSION` présent), puis renommé en `postgresql/`. Le nouveau compose est
posé ensuite et le service redémarre dessus. Un échec relance l'appli sur
l'ancien compose et son volume, supprime la copie partielle et fait échouer
le play : PostgreSQL ne démarre jamais sur un dossier vide ou à moitié copié.
Un deuxième passage ne fait rien. Arrêt attendu : la durée de la copie (base
de quelques dizaines de Mo : quelques secondes) plus l'arrêt et le démarrage
des deux conteneurs, de l'ordre de la minute.

**L'ancien volume n'est pas supprimé** : c'est le filet de retour arrière.

- Retour arrière : remettre l'ancien compose (revert du commit, déployer :
  le compose rend de nouveau `jellystat_postgres_data`) ; le volume porte les
  données d'avant la migration, celles écrites depuis sont perdues (ou à
  rejouer depuis `postgresql/`). Si `postgresql/` est non vide et qu'il faut
  refaire la migration : `systemctl --user stop dc@jellystat`, `sudo rm -rf
  /opt/apps/jellystat/postgresql`, redéployer le rôle migré.
- Suppression, à lancer à la main une fois la base vérifiée (quelques jours,
  une sauvegarde borg passée) : `docker volume rm jellystat_postgres_data`. Le
  volume est sous `/var/lib/docker/volumes` : tant qu'il existe il n'est plus
  écrit, donc sans effet sur auditd. Retirer ensuite
  `tasks/migrate_postgres_volume.yml` et son `include_tasks` (PR à part).

## Durcissement

Image Docker Hub `cyfershepard/jellystat`, tag et digest épinglés ; base
`postgres:18.6-alpine` du même digest que HealthLog. L'appli tourne sous l'uid de
déploiement (l'image est en root par défaut), en lecture seule, `cap_drop:
ALL`, `no-new-privileges`, `tmpfs` sur `/tmp`, le seul dossier écrit est
`backup-data/` (lié depuis le dossier du rôle). Essayé en local (podman, mêmes
options, avec une base PostgreSQL 18) : migrations passées, `GET
/auth/isconfigured` répond 200 (`{"state":0,…}`), la sonde `wget` du
healthcheck passe (elle vise `127.0.0.1` : `localhost` se résout d'abord en
`::1`, où l'appli n'écoute pas). Deux messages du journal sans gravité : `Error
writing env.js` (l'appli écrit `dist/env.js` pour les variables `JS_*` du
navigateur, lues avec `?.`) et, avec une base qui ne porte pas le nom de
l'utilisateur, `database "…" does not exist` (le rôle donne ce nom à la base
pour l'éviter : non essayé tel quel). L'appli met plus de 10 s à s'arrêter sur
SIGTERM (npm en PID 1) : SIGKILL au `compose stop`, sans conséquence, l'état
est dans la base.

`mem_limit` : 512m (appli, ~100 Mio au repos mesurés en local, sans Jellyfin
joignable) et 512m + `mem_reservation: 128m` (base). Valeurs prudentes, **à
remesurer** (`memory.peak`, rapport `mem_report`) après une semaine et une
synchronisation complète.

## Non vérifié

Le déploiement réel, la connexion à Jellyfin (aucun Jellyfin local), l'assistant
de premier lancement avec `JF_HOST`/`JF_API_KEY` déjà posés, le dump
`pg_dump` vers le Storage Box, le cas « clé absente » sous Molecule.
