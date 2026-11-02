# Sauvegarde en échec, restauration d'une appli depuis Borg

Rappels : borgmatic tourne en **root** (`/root/.local/bin/borgmatic`), une
config par appli dans `/etc/borgmatic.d/<app>.yaml`, lancées toutes ensemble
par `borgmatic.timer` à 01:00. Chaque hôte parle à **son** sous-compte de la
Storage Box (`backup-<hôte>`, port 23, clé
`/root/.ssh/borgmatic_storage_box_ed25519`, alias SSH `backup_storage_box`
dans `/root/.ssh/config`).

Exception, le **NAS** (Jellyfin) : rien n'est installé sous UGOS, borgmatic
tourne dans son image (`docker compose run --rm`), lancé par le même
`borgmatic.timer`, à 02:30. Partout ci-dessous, y remplacer
`/root/.local/bin/borgmatic` par l'enrobage
`/volume1/docker/borgmatic/borgmatic` et `/etc/borgmatic.d` par
`/volume1/docker/borgmatic/borgmatic.d` (monté aussi en `/etc/borgmatic.d`
dans le conteneur) ; clé et `known_hosts` dans
`/volume1/docker/borgmatic/ssh/`. Pas d'alias `backup_storage_box` :
`sudo /volume1/docker/borgmatic/borgmatic --config
/volume1/docker/borgmatic/borgmatic.d/jellyfin.yaml list` teste aussi
l'accès au sous-compte. Le conteneur disparaît après chaque commande :
extraire vers un dossier monté (`--destination
/volume1/docker/borgmatic/restore`), jamais vers un chemin du seul conteneur.
`sqlite3` est celui de l'image.

## Symptôme

- Le moniteur push de sauvegarde de l'appli (groupe Backups d'Uptime Kuma)
  passe DOWN : le run a signalé un échec, ou aucun push depuis 25 h
  (`uptimekuma_monitor_push.backup`, `tofu/pangolin_config/websites.tf`,
  fenêtre `local.backup_push_interval`).
- Ou : `borgmatic.service` en `failed` sur l'hôte.
- Ou : des données à récupérer (fausse manipulation, base corrompue).

## Diagnostic

Sur l'hôte de l'appli (exemple : `rss` sur la VM docker).

```bash
systemctl status borgmatic.timer borgmatic.service
sudo journalctl -u borgmatic.service -n 300 --no-pager
```

Ne pas lancer `journalctl --since -30days` sur la VM docker : lire tout le
journal sur son disque (SSD SATA d'entrée de gamme de l'hôte) fait monter la charge à plus de 30.

Erreurs courantes :

| Message | Cause probable |
|---|---|
| `Permission denied (publickey)` | la clé de root n'est pas autorisée chez le sous-compte (hôte neuf ou reconstruit) |
| `Host key verification failed` | clé d'hôte de la Storage Box absente de `/root/.ssh/known_hosts` |
| `Failed to create/acquire the lock` | un run précédent interrompu a laissé un verrou |
| erreur de `mariadb-dump` / `pg_dump` | conteneur de la base arrêté ou renommé |
| erreur `sqlite3` | base SQLite déplacée ou supprimée depuis le déploiement |
| `passphrase supplied … is incorrect` | `backup_passphrase` changée dans SOPS sans migrer les dépôts |

Tester à la main :

```bash
sudo ssh backup_storage_box ls                      # le sous-compte répond-il ?
sudo /root/.local/bin/borgmatic --config /etc/borgmatic.d/rss.yaml list
sudo /root/.local/bin/borgmatic --config /etc/borgmatic.d/rss.yaml --verbosity 1   # un run complet de cette appli
```

## Réparation

- **Clé non autorisée** (hôte neuf ou reconstruit) : l'ordre de
  `ansible/backup.yaml`.

  ```bash
  cd ansible
  ansible-playbook <playbook de l'hôte> --tags setup   # le rôle borgmatic génère la clé
  ansible-playbook backup.yaml                          # l'autorise chez le sous-compte
  ansible-playbook <playbook de l'hôte>                 # repo-create et configs borgmatic
  ```

- **Verrou orphelin** (aucun borgmatic en cours, `pgrep -a borg` vide) :

  ```bash
  sudo /root/.local/bin/borgmatic --config /etc/borgmatic.d/rss.yaml break-lock
  ```

- **Dump en échec** : remettre la base en route
  ([appli-en-panne.md](appli-en-panne.md)), puis relancer un run.
- **Config borgmatic fausse ou périmée** : redéployer la partie sauvegarde
  du rôle : `ansible-playbook docker.yml --tags backup`.

## Restaurer une appli

La procédure pas à pas (arrêt, `borgmatic extract`, copie, `borgmatic
restore` des dumps SQL, cas SQLite) est dans
[../backup-restore.md](../backup-restore.md). Les points à ne pas rater :

1. **Arrêter l'appli** avant : `systemctl --user stop dc@rss` (Pangolin :
   `sudo systemctl stop pangolin`).
2. **Choisir l'archive** : `borgmatic list` montre les archives
   `<app>-<date>` ; `--archive latest` prend la dernière.
3. **Extraire dans un dossier de travail**, jamais directement sur `/` :
   `--destination /root/restore/<app>`. Les chemins n'ont pas de `/`
   initial. borgmatic 2.1 y met aussi, hors des sources de l'appli, ses
   dumps SQL (`borgmatic/postgresql_databases/<conteneur>:<port>/<base>`,
   format custom de `pg_restore`) et **toutes** les configs
   `etc/borgmatic.d/*.yaml` de l'hôte (amorçage de `borgmatic bootstrap`).
4. **Bases PostgreSQL / MariaDB** : le **conteneur de base seul** démarré
   (`docker compose up -d <base>` dans `/opt/apps/<app>`), l'appli arrêtée
   (sinon elle écrit ou migre pendant le rejeu), puis `borgmatic restore
   --config /etc/borgmatic.d/<app>.yaml --archive latest`. borgmatic joint
   la base par l'IP du conteneur avec le client **de l'hôte** (`pg_restore`
   17.11 sur la VM docker, qui lit les dumps de PostgreSQL 18.6 ; s'il
   refusait un dump plus récent, le rejouer avec celui du conteneur :
   [healthlog.md](healthlog.md#restauration-depuis-borg)).
5. **Bases SQLite** : la copie est dans l'archive sous
   `var/lib/borgmatic-sqlite/<app>/`, nommée d'après son chemin d'origine
   (`/` remplacés par `_`) ; la base vivante est exclue de l'archive, donc
   recopier le dossier de l'appli ne la remplace pas. Vérifier la copie
   (`sqlite3 <copie> 'PRAGMA integrity_check'` : `ok`). Appli arrêtée, la
   remettre en place en supprimant les `-wal` et `-shm` de l'ancienne (un
   WAL resté là serait rejoué sur la copie), puis lui rendre son
   propriétaire : la copie sort `root:root` (`stat -c %u:%g` sur l'ancienne
   avant, `chown` après ; `borgmatic/defaults/main.yml`). Elle sort aussi en
   `journal_mode=delete` (`VACUUM INTO`) : si l'ancienne était en WAL
   (`sqlite3 <ancienne> 'PRAGMA journal_mode'` avant), remettre la copie en
   WAL avant de démarrer l'appli (`sqlite3 <copie> 'PRAGMA
   journal_mode=WAL'`), sinon le hook de sauvegarde, qui choisit à chaque run
   d'après ce mode, passe à `.backup`, qui ne finit jamais sur une base
   écrite sans cesse (README du rôle `borgmatic`).
6. **Dépôt lui-même effacé ou abîmé** : les snapshots de la Storage Box
   (9 quotidiens, `tofu/pangolin/storage_box.tf`) se restaurent depuis la
   console Hetzner (Storage Box → Snapshots), avec le compte principal.
   Procédure exacte : à vérifier dans la console.

## Restauration d'essai (sans toucher à l'appli)

Dans `/root/restore-drill/<app>` (`0700`, root), jamais sur `/` ni dans
`/opt/apps`, l'appli vivante laissée en marche. Fait le 02/11/2026 pour
HealthLog et Papra.

- **PostgreSQL** : base jetable de la même image, en tmpfs, sans port
  publié ni `newt`, et `borgmatic restore --container <conteneur jetable>`
  y détourne le rejeu ; l'appli jetable sur un réseau `--internal` prouve
  que la clé de l'archive ouvre les colonnes chiffrées. Commandes :
  [healthlog.md](healthlog.md#restauration-dessai-sans-toucher-a-lappli).
- **SQLite et fichiers** (exemple Papra, 795 Mo, extract en 21 s), en root :

  ```bash
  d=/root/restore-drill/papra
  install -d -m 0700 $d
  /root/.local/bin/borgmatic --config /etc/borgmatic.d/papra.yaml extract --archive latest --destination $d
  for f in $d/var/lib/borgmatic-sqlite/papra/*.sqlite; do sqlite3 -readonly "$f" 'PRAGMA integrity_check'; done   # ok
  db=$d/var/lib/borgmatic-sqlite/papra/opt_apps_papra_app-data_db_db.sqlite
  q='select count(*), sum(original_size) from documents'
  sqlite3 -readonly "$db" "$q"; sqlite3 -readonly 'file:/opt/apps/papra/app-data/db/db.sqlite?mode=ro' "$q"
  # un échantillon de fichiers : empreinte de la base = copie restaurée = fichier vivant
  sqlite3 -separator ' ' -readonly "$db" 'select original_sha256_hash, original_storage_key from documents order by random() limit 5' |
    while read -r h k; do
      echo "$h  $d/opt/apps/papra/app-data/documents/$k"
      echo "$h  /opt/apps/papra/app-data/documents/$k"
    done | sha256sum -c --quiet && echo 'échantillon OK'
  ```

  Un échantillon, pas tout : le disque de la VM docker est lent.

Ranger ensuite : `sudo rm -rf /root/restore-drill/<app>`.

## Vérification

```bash
sudo /root/.local/bin/borgmatic --config /etc/borgmatic.d/rss.yaml --verbosity 1
sudo /root/.local/bin/borgmatic --config /etc/borgmatic.d/rss.yaml list --last 1
```

Le moniteur push repasse UP. Après une restauration : l'appli répond, et ses
données sont celles attendues.

## Prévention

- Une restauration d'essai de temps en temps (plus haut ; la dernière :
  HealthLog et Papra, 02/11/2026) : c'est le seul vrai test d'une
  sauvegarde. Le test de restauration de la CI
  (`.github/restore-test/README.md`) rejoue les bases et extrait 20
  fichiers chaque quinzaine, sans les comparer au vivant ni démarrer
  l'appli (la clé de chiffrement de HealthLog n'y est pas éprouvée).
- Garder `backup_passphrase` hors du seul SOPS (gestionnaire de mots de
  passe) : sans elle, aucun dépôt ne s'ouvre.
- borgmatic vérifie le dépôt toutes les 2 semaines et les archives tous les
  mois (`checks:` du modèle `app.yaml.j2`).

## Sauvegarde vzdump de Proxmox (VM docker, LXC newt)

Borg sauvegarde les applis ; le job vzdump de Proxmox (`tofu/proxmox/backup.tf`,
21:00, `keep-last=2`) sauvegarde la VM docker (id 100) et le LXC newt (200)
entiers, sur le storage `nas-backup` : l'export NFS `/volume1/pve-backup` du
NAS (`host_vars/nas`, publié par `nas.yml` pour l'IP de l'hôte, 192.168.1.26).
Plus sur `local` : la racine de l'hôte (94 Go) ne tient pas trois archives de la
VM docker (vzdump écrit la nouvelle avant d'élaguer les anciennes), d'où les
« No space left on device » chaque soir du 30/09 au 27/10/2026.

Mise en place, dans l'ordre :

1. UGOS : dossier partagé `pve-backup`, corbeille décochée, sans instantanés
   (ou avec une rétention courte : une archive élaguée reste sinon dans les
   instantanés), sans partage SMB ni accès d'autres utilisateurs : les
   archives ne sont pas chiffrées (disque entier de la VM docker, donc les
   secrets de toutes les applis) et UGOS les crée en 0777.
2. `ansible-playbook nas.yml` (depuis `ansible/`), puis depuis l'hôte :
   `showmount -e 192.168.1.137` liste `/volume1/pve-backup 192.168.1.26`.
3. `tofu/proxmox` : `tofu init` (le lock versionné fixe le provider ≥ 0.116),
   puis
   `tofu import proxmox_backup_job.nightly backup-cbfcde61-8413` (le job créé
   dans l'interface), puis `tofu plan` : création du storage, `storage` du job
   `local` → `nas-backup`, rien d'autre. `tofu apply`, puis
   `ansible-playbook pve.yml --tags vzdump` (`tmpdir: /var/tmp` dans
   `/etc/vzdump.conf`).
4. Lancer le job une fois (Datacenter → Sauvegarde → Exécuter maintenant), puis
   faire de la place sur `local` : les deux archives de la VM docker du 28 et
   29/09 (`/var/lib/vz/dump/vzdump-qemu-100-*`, ~51 Gio), l'archive partielle du
   29/08 (`.vma.dat` et son `.tmp`), les archives du LXC 200 et de l'ancien
   LXC 102.

Diagnostic d'un échec : le journal de la tâche (interface, ou
`/mnt/pve/nas-backup/dump/*.log`), `pvesm status` (`nas-backup` actif ?), un
`tar: …/vzdump-lxc-200-….tmp: Cannot open: Permission denied` (dossier
temporaire sur le NFS, que le tar du LXC non privilégié ne peut pas ouvrir : le
`tmpdir: /var/tmp` de `/etc/vzdump.conf` manque : `ansible-playbook pve.yml
--tags vzdump`), un échec d'allocation de l'image de fleecing (`lvs` : `data%`
du pool de `local-lvm` ; une image `vm-100-fleece-*` restée après un job
interrompu se retire par `pvesm free local-lvm:vm-100-fleece-0`, après avoir
relu son nom, hors job), et
la taille de la VM : `df -h /` et `docker system df` dans la VM. Les images
Docker remplacées par Renovate grossissent chaque archive tant qu'elles restent
sur le disque : `docker-image-prune.timer` (rôle `docker_service`) les retire
chaque dimanche, ou `docker image prune -a` à la main.

Ces archives sont restaurées à l'essai le 2 et le 16 du mois sur l'hôte
(LXC démarré sans réseau, archive de la VM vérifiée en entier) :
[test-restauration-vm.md](test-restauration-vm.md).
