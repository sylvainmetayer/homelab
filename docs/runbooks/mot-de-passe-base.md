# Changer le mot de passe d'une base Postgres ou MariaDB

Procédure, pas un incident : le mot de passe d'une base a fuité, ou on veut
simplement le renouveler. Rare, donc documentée plutôt que scriptée.

## Le piège

Postgres (`POSTGRES_PASSWORD`) et MariaDB (`MYSQL_PASSWORD`,
`MYSQL_ROOT_PASSWORD`) ne lisent leur variable d'environnement qu'à
l'**initialisation** d'un datadir vide. Changer la valeur dans
`ansible/secrets.sops.yaml` puis redéployer ne change donc rien en base :
l'appli se connecte avec le nouveau mot de passe, la base attend l'ancien,
l'appli tombe.

Le dump borgmatic de la nuit tombe avec elle. La configuration générée
(`ansible/roles/borgmatic/templates/app.yaml.j2`) prend le mot de passe de
l'entrée `password` de `borgmatic_app_postgresql_databases` /
`borgmatic_app_mysql_databases`, que chaque rôle remplit avec la **même
variable** que son compose. Grâce à la clé `container:`, borgmatic 2.1 lit
l'IP du conteneur (`docker container inspect`) et passe `--host <cette IP>`
au client lancé par `docker exec` : la connexion se fait en TCP, mot de passe
vérifié (`scram-sha-256` pour Postgres), et non par la socket locale, où
l'image officielle de Postgres fait confiance à tout le monde (`trust`). Un
dump en échec fait échouer la configuration de l'appli : borgmatic pousse
`fail` vers le moniteur `Backup <app>` (états `start`, `finish`, `fail` de
`app.yaml.j2`), qui passe rouge et alerte par e-mail aussitôt.

D'où l'ordre : **d'abord la base (`ALTER`), ensuite SOPS et le
redéploiement**, coup sur coup. Entre les deux, les connexions déjà ouvertes
par l'appli continuent de marcher (ni Postgres ni MariaDB ne coupent une
session quand son mot de passe change), seules les nouvelles échouent.

## D'où vient chaque mot de passe

| Appli (rôle) | Hôte, playbook, tag | Conteneur de la base (image) | Utilisateur de l'appli et du dump | Source du mot de passe | Autres lecteurs du mot de passe |
|---|---|---|---|---|---|
| Immich (`immich`) | pi, `pi.yml`, `immich` | `immich_postgres` (`ghcr.io/immich-app/postgres:14-…`) | `postgres` (superutilisateur), base `immich` | SOPS `immich_db_password` | `.env` (`DB_PASSWORD`, templaté) ; le worker distant du poste, `compose/immich/.env` (à la main, hors dépôt) : Postgres est publié en 5432 sur le LAN |
| Dawarich (`dawarich`) | docker, `docker.yml`, `dawarich` | `dawarich-db` (`postgis/postgis:17-3.5-alpine`) | `dawarich`, base `dawarich` | **dérivé** : `sha256(backup_passphrase ~ '-dawarich-db')` (`defaults/main.yml`) | `.env` (`DATABASE_PASSWORD`, templaté) |
| Paperless-ngx (`paperless_ngx`) | docker, `docker.yml`, `paperless` | `paperless_db` (`postgres:18`) | `paperless`, base `paperless` | SOPS `paperless_db_password` | compose (`PAPERLESS_DBPASS`). **En pause** : voir plus bas |
| Nginx demo (`nginx_demo`) | docker, `docker.yml`, `nginx_demo` | `nginx-demo-db` (`postgres:18.6-alpine`) | `nginx_demo`, base `nginx_demo_db` | **fichier tiré une fois** sur le NAS : `/mnt/nas/apps/nginx_demo/db_password` (root, `0600`), relu à chaque déploiement | `.env` (`NGINX_DEMO_DB_PASSWORD`, templaté) |
| Flip Planning, production (`flip_planning`) | flip, `flip.yml`, `flip_planning` | `flip-planning-db` (`postgres:18.6`) | `festival`, base `festival` | SOPS `prod_planning_db_password` (`vars:` de l'entrée de `flip.yml`) | `.env` (`DB_PASSWORD`, templaté) |
| Flip Planning, démo | flip, `flip.yml`, `demo_planning` | `demo-planning-db` | `festival`, base `festival` | SOPS `demo_planning_db_password` | idem |
| Flip Planning, démo Keycloak | flip, `flip.yml`, `demo_planning_kc` | `demo-planning-kc-db` et `demo-planning-kc-keycloak-db` | `festival` (base `festival`) et `keycloak` (base `keycloak`) | SOPS `demo_planning_kc_db_password` et `demo_planning_kc_keycloak_db_password` | `.env` ; compose (`KC_DB_PASSWORD` de Keycloak) |
| Betisier (`betisier`) | docker, `docker.yml`, `betisier` | `betisier_db` (`lscr.io/linuxserver/mariadb:11.8.9`) | `betisier` ; root a le même mot de passe | SOPS `betisier_db_password` | `/opt/apps/betisier/config/config.inc.php` (`DBPASSWD`, à la main) |
| Monica (`monica_v4`) | docker, `docker.yml`, **`monica`** | `monica_v4_db` (linuxserver 11.8.9) | `monica` ; root a le même mot de passe | SOPS `monica_v4_db_password` | `/opt/apps/monica_v4/.env` (`DB_PASSWORD`, à la main : `env_file` non templaté) |
| Nextcloud (`nextcloud`) | docker, `docker.yml`, `nextcloud` | `nextcloud_db` (`mariadb:12.3.3`, image officielle) | `nextcloud` ; root a le même mot de passe | SOPS `nextcloud_db_password` | `config.php` de Nextcloud (`dbpassword`) : le conteneur `nextcloud` ne reçoit aucune variable de base |
| BookStack (`wiki`) | docker, `docker.yml`, `wiki` | `bookstack_db` (linuxserver 11.8.9) | `bookstack` ; root a le même mot de passe | SOPS `wiki_db_password` (le défaut du rôle, `wiki`, n'est jamais utilisé) | `/opt/apps/wiki/config/www/.env` (`DB_PASSWORD`). Le `DB_PASS` du compose est ignoré : l'image actuelle ne lit que `DB_PASSWORD`, dans ce `.env` |

Aucun autre rôle ne lance de Postgres ni de MariaDB. La démo Keycloak n'est
pas sauvegardée (`flip_planning_backup_enabled: false` dans `flip.yml`) :
pas de dump à vérifier pour elle.

Sur les MariaDB, root et l'utilisateur de l'appli partagent la même clé SOPS
(`MYSQL_ROOT_PASSWORD` et `MYSQL_PASSWORD` du compose) : on change les deux,
sinon le SOPS ment sur root. Les comptes root ne sont pas les mêmes selon
l'image :

- **image officielle** (`mariadb:*`, Nextcloud) : `root@localhost` et
  `root@%` ont le mot de passe ; on se connecte en root avec
  `MYSQL_ROOT_PASSWORD`, lu dans l'environnement du conteneur ;
- **linuxserver** (`lscr.io/linuxserver/mariadb`, Betisier, Monica,
  BookStack) : seul `root@%` a un mot de passe, `root@localhost` (socket du
  conteneur) n'en a **pas**, l'image le crée ainsi
  (`/etc/s6-overlay/s6-rc.d/init-mariadb-initdb/run`). On s'y connecte donc
  sans mot de passe, et on ne touche pas à ce compte.

## Avant de commencer

- Pas pendant la sauvegarde de la nuit : `borgmatic.timer` part à 01:00 et
  `borgmatic.service` enchaîne ensuite les configurations de l'hôte une à
  une, parfois longtemps. Un dump lancé entre l'`ALTER` et le redéploiement
  échouerait. Sur l'hôte, `systemctl is-active borgmatic.service` doit
  répondre `inactive`.
- Ne pas merger, pendant l'opération, de PR qui touche le rôle de l'appli :
  `deploy-docker-app` redéploierait depuis `main`, donc avec l'ancien
  mot de passe.
- Une appli en pause (Paperless-ngx aujourd'hui) n'a pas sa base démarrée :
  ne pas tourner son mot de passe pendant la pause. Le faire après la reprise
  ([app-en-pause.md](app-en-pause.md)), appli de nouveau en marche.

Tout se lance **depuis `ansible/`**, mise actif. Le nouveau mot de passe
naît sur le poste, dans un dossier `0700` sur tmpfs, et n'apparaît jamais sur
une ligne de commande (ni `ps`, ni historique du shell, ni `ansible/run.log`).
Hexadécimal : rien à échapper en SQL, en YAML ou dans un fichier PHP.

```bash
cd ansible
appli=monica_v4                 # rôle, cf. tableau
cle=monica_v4_db_password       # clé SOPS, cf. tableau
umask 077
r=/dev/shm/rotation-$appli; mkdir -p "$r"
sops decrypt --extract "[\"$cle\"]" secrets.sops.yaml > "$r/ancien"   # pour le retour arrière
# Dawarich n'a pas de clé SOPS (mot de passe dérivé, cf. tableau) : la ligne
# ci-dessus échoue, l'ancien se recalcule comme le fait le rôle.
# printf '%s-dawarich-db' "$(sops decrypt --extract '["backup_passphrase"]' secrets.sops.yaml)" | sha256sum | cut -d' ' -f1 > "$r/ancien"
test -s "$r/ancien" || echo "ancien vide : pas de retour arrière possible, s'arrêter"
openssl rand -hex 24 > "$r/nouveau"
```

Une fonction pour passer une commande à l'hôte **avec l'entrée standard**
(c'est par là que voyage le SQL qui contient le mot de passe). Elle reprend
les tâches `mise run ssh*` : clé d'hôte vérifiée contre `ansible/known_hosts`,
rebond par Pangolin pour flip.

```bash
ssh_hote() {  # ssh_hote <docker|pi|flip> '<commande distante>'
  # </dev/null : l'entrée standard (le SQL) est pour ssh, pas pour
  # l'inventaire ni les `tofu show` qu'il lance.
  local h ip; h=$(ansible-inventory --host "$1" </dev/null) || return 1
  ip=$(jq -er .ansible_host <<<"$h") || return 1
  eval "ssh -i ~/.ssh/keepassxc.pub -o UserKnownHostsFile=known_hosts -o StrictHostKeyChecking=yes $(jq -r '.ansible_ssh_common_args // ""' <<<"$h") sylvain@$ip \"\$2\""
}
```

## Réparation (la rotation)

### 1. Postgres : `ALTER ROLE` dans le conteneur

Immich, Dawarich, Paperless-ngx, Flip Planning (chaque instance, et la base
Keycloak de la démo Keycloak). Exemple Immich :

```bash
hote=pi ctr=immich_postgres user=postgres db=immich
printf 'ALTER ROLE "%s" PASSWORD '\''%s'\'';\n' "$user" "$(cat "$r/nouveau")" > "$r/alter.sql"
ssh_hote "$hote" "docker exec -i $ctr psql -U $user -d $db -v ON_ERROR_STOP=1" < "$r/alter.sql"
```

Réponse attendue : `ALTER ROLE`. `psql` passe par la socket du conteneur
(`trust`) : aucun mot de passe à fournir pour entrer.

Nginx demo fait exception, son mot de passe n'est pas dans SOPS mais dans un
fichier du NAS. Tout se fait sur la VM (`mise run ssh`) :

```bash
f=/mnt/nas/apps/nginx_demo/db_password
sudo cp -p "$f" "$f.ancien"
sudo sh -c "umask 077; openssl rand -hex 24 | tr -d '\n' > $f; chmod 0600 $f"
sudo sed "s/.*/ALTER ROLE nginx_demo PASSWORD '&';/" "$f" \
  | docker exec -i nginx-demo-db psql -U nginx_demo -d nginx_demo_db -v ON_ERROR_STOP=1
```

Le `chmod` explicite compte : UGOS crée tout en `0777` quel que soit
l'umask. Puis passer directement au redéploiement (étape 3), sans SOPS.

### 1 bis. MariaDB : `ALTER USER` dans le conteneur

Monica, Nextcloud, BookStack. Exemple Monica :

```bash
hote=docker ctr=monica_v4_db user=monica
# linuxserver (monica_v4, wiki) : root@localhost sans mot de passe
racine='exec mariadb -u root'
# image officielle (nextcloud) : mot de passe de root lu dans l'environnement
# racine='MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mariadb -u root'

# Les comptes à changer : l'appli et root, là où ils ont un mot de passe.
echo "SELECT CONCAT(QUOTE(user), '@', QUOTE(host)) FROM mysql.user WHERE user IN ('$user', 'root') AND authentication_string <> '';" \
  | ssh_hote "$hote" "docker exec -i $ctr sh -c '$racine -N'" > "$r/comptes"
cat "$r/comptes"      # Monica : 'root'@'%' et 'monica'@'%' ; Nextcloud : root@localhost en plus
while read -r compte; do
  printf "ALTER USER %s IDENTIFIED BY '%s';\n" "$compte" "$(cat "$r/nouveau")"
done < "$r/comptes" > "$r/alter.sql"
ssh_hote "$hote" "docker exec -i $ctr sh -c '$racine'" < "$r/alter.sql"
```

Aucune sortie = réussi. `MYSQL_PWD` reste dans l'environnement du conteneur,
jamais dans les arguments d'une commande.

**Betisier** ne passe pas par là : sa base n'a pas de volume nommé, le
service `betisier-reset` (`docker compose down` puis `up`, chaque jour) la
recrée depuis `dump.sql` avec le mot de passe du compose. Après SOPS et le
redéploiement (étapes 2 et 3), lancer `systemctl --user start
betisier-reset.service` sur la VM : base neuve, nouveau mot de passe. Un
simple redéploiement ne suffit pas : compose réutilise le volume anonyme
(`/config`) du conteneur recréé, donc l'ancienne base.

### 2. Les autres lecteurs, puis SOPS

D'abord les fichiers écrits à la main que liste la dernière colonne du
tableau, sur l'hôte (`mise run ssh`), avec un éditeur (`sudo` si le fichier
n'est pas à `sylvain`), en collant le contenu de `$r/nouveau` :

- Monica : `DB_PASSWORD=` de `/opt/apps/monica_v4/.env` ;
- BookStack : `DB_PASSWORD=` de `/opt/apps/wiki/config/www/.env` ;
- Betisier : `define('DBPASSWD', "…");` de
  `/opt/apps/betisier/config/config.inc.php` ;
- Nextcloud : `'dbpassword' => '…',` du `config.php`, que trouve
  `sudo grep -rl "'dbpassword'" /opt/apps/nextcloud/config --include=config.php`
  (`www/nextcloud/config/config.php` chez linuxserver) ;
- Immich : `DB_PASSWORD=` de `compose/immich/.env` sur le poste, si le worker
  distant sert encore.

Puis SOPS, sur le poste. `--value-stdin` attend une **chaîne JSON** (entre
guillemets) : un mot de passe nu est refusé (« Value for --set is not valid
JSON »), ce qui ne laisse rien à moitié écrit. `printf` est une commande
interne du shell, la valeur ne passe dans aucun `ps` :

```bash
printf '"%s"' "$(cat "$r/nouveau")" | sops set --value-stdin secrets.sops.yaml "[\"$cle\"]"
git diff --stat secrets.sops.yaml   # une seule clé change (plus les métadonnées sops)
```

**Dawarich** n'a pas de clé SOPS : son mot de passe est dérivé de
`backup_passphrase`, qu'on ne change pas pour ça. Créer la clé
`dawarich_db_password` (même commande, elle prime sur le défaut du rôle :
SOPS est dans la couche `include_vars`) et ajouter une valeur factice
`dawarich_db_password` à `ansible/molecule/_shared/vars/fake_secrets.yml`,
comme pour toute nouvelle clé lue par un rôle.

### 3. Redéployer l'appli

```bash
ansible-playbook docker.yml --tags monica --check --diff   # puis sans --check
```

Playbook et tag : colonne « Hôte » du tableau (`pi.yml --tags immich`,
`flip.yml --tags demo_planning`…). Le rôle réécrit compose et `.env`
(`diff: false` : le `--diff` ne montre pas leur contenu, seulement
« changed ») et la configuration borgmatic (`/etc/borgmatic.d/<appli>.yaml`),
puis son handler redémarre `dc@<appli>`, ce qui recrée les conteneurs dont
l'environnement a changé.

### 4. Pousser le changement de SOPS

Branche, commit de `ansible/secrets.sops.yaml` (et `fake_secrets.yml` pour
Dawarich), PR, merge sans attendre : tant que `main` porte l'ancien mot de
passe, le prochain déploiement CI de ce rôle le remettrait. Puis effacer les
fichiers de travail : `rm -r "$r"` (et `sudo rm
/mnt/nas/apps/nginx_demo/db_password.ancien` pour Nginx demo).

## Vérification

1. L'appli répond : son moniteur Uptime Kuma est vert, `docker ps` montre la
   base et l'appli `healthy` ou `Up`, les journaux de l'appli
   (`docker logs --since 10m <conteneur de l'appli>`) n'ont pas
   d'`authentication failed` / `Access denied`.
2. Le dump passe, avec le vrai chemin de borgmatic (TCP vers l'IP du
   conteneur) : une sauvegarde de cette appli seule, sur son hôte,

   ```bash
   sudo /root/.local/bin/borgmatic --config /etc/borgmatic.d/<appli>.yaml create --verbosity 1
   ```

   Elle crée une vraie archive et pousse vers `Backup <appli>`, c'est voulu.
   `--dry-run` ne prouverait rien : borgmatic n'y lance aucun dump. Le nom du
   fichier est celui de `borgmatic_app_name` (`immich`, `monica_v4`,
   `flip_planning`, `demo_planning`…), `ls /etc/borgmatic.d` au besoin.
3. Le test de restauration (le 1er et le 15, `.github/restore-test/`) n'est
   pas concerné : il rejoue le dump dans un conteneur jetable, et un dump ne
   contient pas le mot de passe de l'utilisateur (`pg_dump` d'une base, comme
   `mariadb-dump`, n'emporte pas les comptes).

## Retour arrière

L'appli ne repart pas et la cause n'est pas évidente : remettre l'ancien
mot de passe, par le même chemin.

1. En base : refaire l'étape 1 (ou 1 bis) avec `$r/ancien` à la place de
   `$r/nouveau`. Exception, Nextcloud **avant** le redéploiement : son
   `MYSQL_ROOT_PASSWORD` est encore l'ancien alors que root a déjà le
   nouveau ; entrer à la main, `docker exec -it -e MYSQL_HISTFILE=/dev/null
   nextcloud_db mariadb -u root -p`, en collant `$r/nouveau`. Nginx demo :
   `sudo cp -p "$f.ancien" "$f"`, puis la seule commande `sudo sed … |
   docker exec …` de l'étape 1 (pas l'`openssl`, qui tirerait un troisième
   mot de passe). Betisier n'a rien à refaire en base : son
   `betisier-reset.service`, relancé après le redéploiement, la recrée avec
   le mot de passe remis.
2. SOPS : `git checkout -- secrets.sops.yaml` si le changement n'est pas
   encore commité, sinon `git revert` du commit, et les fichiers à la main de
   l'étape 2 remis à l'ancienne valeur.
3. Redéployer (étape 3), vérifier (ci-dessus).

## Prévention

- Une base neuve d'appli Postgres garde le mot de passe hors de SOPS, tiré
  une fois et rangé à côté du cluster, comme Nginx demo
  (`nginx_demo_db_password_path`) : SOPS ne peut alors plus diverger de la
  base.
- Rien n'automatise la rotation (une tâche Ansible faisant l'`ALTER`) : pas
  justifié tant qu'aucune rotation n'est planifiée.

## Comment cette procédure a été testée

Le 2026-10-28, sur des conteneurs **jetables** du poste (podman), jamais sur
les bases des hôtes, avec les images épinglées par les rôles (majeures
comprises) : `postgres:18.6-alpine` et `postgres:14-alpine` (Immich est en
14), `mariadb:12.3.3` (officielle) et `lscr.io/linuxserver/mariadb:11.8.9`.
Pour chacune : base et utilisateur créés comme le font les composes, rotation
avec les commandes ci-dessus (`ssh_hote` remplacé par un shell local),
ancien mot de passe refusé et nouveau accepté depuis un autre conteneur du
même réseau (le chemin de l'appli), dump à la façon de borgmatic (`docker
exec`, `--host` = IP du conteneur) en échec avec l'ancien et réussi avec le
nouveau, puis conteneurs et réseau supprimés. Testés aussi : le refus d'une
valeur non JSON par `sops set --value-stdin` (sops 3.13.3, sur un fichier
SOPS jetable), le `sed` de Nginx demo, la fonction `ssh_hote` (arguments
reçus par un faux `ssh`, `ProxyCommand` de flip compris). Non testés en
conteneur : les fichiers des applis elles-mêmes (`config.php` de Nextcloud,
`.env` de BookStack et Monica, `config.inc.php` de Betisier), lus dans leurs
sources ou leurs images.
