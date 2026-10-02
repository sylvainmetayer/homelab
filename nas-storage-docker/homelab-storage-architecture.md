# Données des applis sur le NAS — Ugreen DXP2800 + VM docker

## Besoin

- Les **données** des applis vivent sur le NAS Ugreen DXP2800 (UGOS Pro,
  `192.168.1.137`).
- Le **compute** reste sur la VM docker de Proxmox (`192.168.1.216`, voir
  `tofu/proxmox`). Elle devient remplaçable : la recréer ne perd aucune
  donnée.
- **Borg reste l'unique sauvegarde** et couvre tout, y compris ce qui est sur
  le NAS : même pipeline que les autres applis (Storage Box Hetzner, chiffré,
  hors site, monitoré par Uptime Kuma).

## Décision : où va quoi

| Donnée | Où | Comment | Sauvegarde borg |
|---|---|---|---|
| Fichiers (uploads, médias, données de l'appli) | NAS | NFSv4.1, export monté sur la VM (`/mnt/nas/apps`), bind mount dans le conteneur | copie des fichiers |
| BDD serveur (Postgres, MariaDB) | NAS | même export, sous-dossier de l'appli | **dump logique** (`postgresql_databases` / `mysql_databases`), jamais la copie du data directory |
| BDD embarquée (SQLite, LMDB, BoltDB…) | disque local de la VM | bind mount sous `/opt/apps/<service>` comme aujourd'hui | `sqlite_databases` ou fichiers |
| Caches (redis/valkey, vignettes régénérables) | disque local de la VM | | aucune |
| `compose.yaml`, `.env` | disque local de la VM | régénérés par Ansible à chaque run | copie, comme aujourd'hui |

Un seul protocole, NFS. Pas d'iSCSI, pas de SMB.

## Pourquoi

### Postgres et MariaDB sur NFS : oui, à deux conditions

La doc PostgreSQL (*Creating a Database Cluster → File Systems → Network File
Systems*) accepte un data directory sur NFS. Le risque qu'elle cite : une
écriture différée (asynchrone) perdue en silence, et un montage `soft`. Les
deux conditions sont donc :

- **montage `hard`** côté VM (rôle `nas_storage`). Sur une coupure du NAS, les
  I/O se figent puis reprennent quand il revient. Avec `soft`, une écriture
  déjà acquittée à Postgres peut échouer après coup.
- **export synchrone** côté NAS (le défaut de knfsd, sur lequel repose UGOS).
  Le serveur n'acquitte un `COMMIT` NFS qu'une fois la donnée sur disque, donc
  un `fsync()` de Postgres sur la VM l'est vraiment.

NFSv4.1 plutôt que v3 : le verrouillage fait partie du protocole (pas de
`lockd`/`statd` à côté, pas de ports dynamiques) et tout passe par le seul port
2049/tcp.

### SQLite sur NFS : non

La FAQ SQLite et la doc du mode WAL sont explicites : les verrous POSIX sont
peu fiables sur beaucoup d'implémentations NFS, et le mode WAL, qui partage un
fichier `-shm` par `mmap`, ne fonctionne pas sur un système de fichiers
réseau. Résultat possible : une corruption silencieuse. Une appli SQLite garde
donc sa base sur le disque local et peut quand même mettre ses fichiers sur le
NAS. Vérifier le moteur avant de migrer une appli : Gramps Web, par exemple,
est en SQLite par défaut.

### Pourquoi pas iSCSI (le plan initial de la PR)

iSCSI donne à la base un vrai disque bloc. C'est son seul avantage, et NFS
`hard` + export `sync` couvre déjà l'exigence de Postgres. En face :

- **Panne du NAS** : NFS `hard` gèle puis reprend tout seul. iSCSI, après le
  timeout de session, renvoie des erreurs d'I/O à la VM : ext4 se remonte en
  lecture seule ou Postgres s'arrête en `PANIC`, et il faut intervenir à la
  main (fsck, remontage, redémarrage).
- **Exploitation** : iSCSI demande une étape manuelle sur Proxmox (`pvesm add
  iscsi` + `lvm`), un disque Tofu par appli et, dans Ansible, mkfs, UUID et
  ordre `/dev/sdX`. Le LVM sur LUN partagé est thick (pas de thin, pas de
  snapshot Proxmox), et le LUN est opaque côté NAS : impossible d'y parcourir
  les fichiers. NFS, c'est une ligne dans fstab et un dossier par appli, créé
  par Ansible.
- **Sauvegarde** : borg a de toute façon besoin d'un dump logique, car copier
  les fichiers d'une base en marche ne donne pas une copie cohérente. Le
  disque bloc n'apporte donc rien à la sauvegarde.

SMB est écarté pour la même raison que SQLite sur NFS : pas de sémantique
POSIX (propriétaires, permissions, verrous) pour les conteneurs.

### Pourquoi borg et pas (seulement) des snapshots Btrfs

Un snapshot vit sur les mêmes disques que la donnée : ce n'est pas une
sauvegarde. Borg est déjà hors site, chiffré, rétention réglée et poussé vers
Uptime Kuma pour chaque appli. Les snapshots Btrfs planifiés sur le NAS restent
**un bon complément**, pour revenir en arrière en quelques secondes après une
migration ratée, mais rien ne les surveille.

### Coût accepté : la latence

Chaque commit fait un aller-retour réseau plus une écriture synchrone sur les
disques du NAS, soit quelques millisecondes. Pour des applis à quelques
utilisateurs, c'est invisible (le disque de la VM est déjà rotatif). Si une
base en souffre un jour, on ramène **seulement son data directory** sur le
disque local : ses fichiers restent sur le NAS et le dump borg ne change pas.

## Comment c'est câblé

### Rôle `nas_storage` (`ansible/roles/nas_storage`)

- Installe `nfs-common`.
- Déclare l'export dans `/etc/fstab` : `vers=4.1,hard,proto=tcp,noatime,_netdev,nofail,x-systemd.automount,x-systemd.mount-timeout=30`,
  puis démarre l'unité `.automount`.
- Installe `/usr/local/bin/nas-storage-wait [timeout]` : attend que l'export
  réponde (sondes `stat -f` tuées par `SIGKILL`, la seule chose qu'un
  processus bloqué sur un montage `hard` écoute) puis sort 0, ou sort 1.
- Installe la slice `nas-storage.slice`, ordonnée après le montage, et un
  drop-in `docker.service` `After=` le montage. Les conteneurs du NAS y sont
  placés (`cgroup_parent`) : à l'arrêt de la VM, systemd les arrête avant de
  démonter le NAS et de couper le réseau. Sans ça, chaque conteneur est une
  scope sans ordre vis-à-vis du montage, et le dernier checkpoint de Postgres
  peut bloquer l'arrêt.
- Vérifie que `/mnt/nas/apps` est bien du NFS (`stat -f` sur le point de
  montage, timeout 60 s) : un NAS injoignable fait échouer le run tout de
  suite, au lieu de laisser un conteneur ou un backup tomber plus tard.

`x-systemd.automount` est le point important. Sans lui, un conteneur démarré
avant le montage (NAS lent au boot) bind-monte le dossier **local vide**
`/mnt/nas/apps/<service>` et y écrit sans que rien ne le signale. Avec, le
premier accès monte l'export ou échoue.

Variables (`roles/nas_storage/defaults/main.yml`) : `nas_storage_server`,
`nas_storage_export`, `nas_storage_mount_path`, `nas_storage_nfs_version`
(repli `"3"` possible sans autre changement).

### Une appli avec ses données sur le NAS

Référence : `ansible/roles/nginx_demo`.

1. `meta/main.yml` : `dependencies: [{role: nas_storage}]`. `--tags <service>`
   monte aussi le NAS, et le rôle ne s'exécute qu'une fois par play. La CI
   (`.github/scripts/resolve_docker_tags.py`) suit ces dépendances : modifier
   `nas_storage` redéploie les applis qui en dépendent.
2. `<service>_data_path: "{{ nas_storage_mount_path }}/<service>"`. Les
   dossiers y sont créés avec `become: true`, sans droits pour « others » :
   chacun appartient à l'uid/gid qui l'utilise dans le conteneur (postgres
   alpine 70, nginx alpine 101, l'utilisateur sinon).
3. `compose.yaml` : bind mounts en chemin absolu vers `<service>_data_path`
   (pas de volume Docker `driver_opts: nfs`, que borg ne pourrait pas lire) et
   `cgroup_parent: {{ nas_storage_slice }}` sur chaque conteneur.
4. Drop-in utilisateur `dc@<service>.service.d/nas-storage.conf` avec
   `ExecStartPre=/usr/local/bin/nas-storage-wait 200`. Au boot, la VM est
   prête avant le NAS ; sans attente, chaque essai de `dc@<service>` échoue
   en 30 s, l'unité atteint `StartLimitBurst` et reste en échec jusqu'à un
   `reset-failed` manuel. Avec ~200 s par essai, elle réessaie jusqu'au
   retour du NAS (rester sous le `TimeoutStartSec` de 300 s de `dc@`).
5. Borgmatic :
   - les dossiers de fichiers du NAS dans `source_directories`, **sans** le
     data directory de la base, qui passe par `postgresql_databases` /
     `mysql_databases` avec `pg_dump_command: docker exec …` ;
   - `source_directories_must_exist: true` ;
   - un hook `before: configuration` qui lance `nas-storage-wait 30`. Il n'y a
     qu'un `borgmatic.service` pour toutes les applis : sur un NAS tombé, un
     montage `hard` bloquerait le backup indéfiniment, et ceux des applis
     suivantes avec lui. L'attente bornée fait échouer cette config seule
     (alerte Uptime Kuma) et borgmatic passe à la suivante. Reste non couvert :
     un NAS qui tombe en plein backup.
6. Mot de passe de la base : tiré une fois et rangé sur le NAS à côté du
   cluster (`<service>_data_path/db_password`, root 0600). Postgres ne lit
   `POSTGRES_PASSWORD` qu'à l'initdb, donc un mot de passe dérivé d'un secret
   partagé (`backup_passphrase`) divergerait de la base au premier changement
   de ce secret, et `pg_dump` échouerait.
7. Retrait de l'appli (`remove-app`) : passer `<service>_data_path` dans
   `decommission_app_extra_paths`, sinon les fichiers et le cluster restent
   orphelins sur le NAS, et un ré-ajout de l'appli réutiliserait en silence
   l'ancien cluster.

## Mise en place côté NAS (une fois, à la main)

UGOS Pro n'a pas d'API publique : rien de ceci n'est automatisable.

1. **Dossier partagé** `apps` sur le volume 1.
2. **Service NFS** : l'activer et cocher NFSv4.1 (Panneau de configuration →
   Services de fichiers → NFS).
3. **Règle NFS** sur le dossier `apps` :
   - client : `192.168.1.216` uniquement (jamais un sous-réseau) ;
   - lecture/écriture ;
   - squash : **No mapping** (équivalent `no_root_squash`). Il le faut pour
     que borg (root sur la VM) lise tout et que l'entrypoint Postgres puisse
     faire `chown` de son data directory. Le risque est contenu parce que la
     règle ne vise que l'IP de la VM ;
   - écriture asynchrone : **désactivée** si l'option existe (export `sync`).
4. Noter le **chemin d'export** affiché par UGOS. S'il diffère de
   `/volume1/apps`, surcharger `nas_storage_export`.
5. Premier test depuis la VM :
   ```bash
   sudo mount -t nfs -o vers=4.1 192.168.1.137:/volume1/apps /mnt && ls -ln /mnt && sudo umount /mnt
   ```
   Si les fichiers apparaissent en `nobody:nogroup` (4294967294), le NAS
   fait du mapping d'identités par nom en v4. Soit on l'aligne, soit on
   repasse `nas_storage_nfs_version: "3"`.
6. (Recommandé) Snapshots Btrfs planifiés sur `apps`, en complément de borg.

Pare-feu entre la VM et le NAS : 2049/tcp suffit en v4.1 (v3 : plus 111 et
les ports dynamiques de `mountd`/`statd`).

## Déployer l'appli pilote

```bash
cd tofu/pangolin_config && tofu plan && tofu apply   # route + monitors nginx-demo
cd ../../ansible
ansible-playbook -i inventory/hosts backup.yaml      # dossier nginx_demo sur la Storage Box
ansible-playbook -i inventory/hosts docker.yml --check --tags nginx_demo
ansible-playbook -i inventory/hosts docker.yml --tags nginx_demo
```

Vérifier :

```bash
findmnt /mnt/nas/apps                                  # nfs4, options hard
docker exec nginx-demo-db psql -U nginx_demo -d nginx_demo_db -c 'select 1'
sudo /root/.local/bin/borgmatic -c /etc/borgmatic.d/nginx_demo.yaml create --stats
sudo /root/.local/bin/borgmatic -c /etc/borgmatic.d/nginx_demo.yaml list --archive latest | grep -E 'html|postgresql'
```

## Restaurer

- **VM perdue** : `tofu apply` (proxmox) puis `docker.yml`. Le NAS est remonté,
  les applis repartent sur leurs données intactes. Rien à restaurer, hors
  données locales (SQLite), qui sortent de borg comme aujourd'hui.
- **NAS perdu** : recréer le partage et la règle, lancer `docker.yml`
  (recrée les dossiers), puis `borgmatic extract` pour les fichiers et
  `borgmatic restore` pour les bases.

## Migrer une appli existante vers le NAS

1. `systemctl --user stop dc@<service>`.
2. `sudo rsync -aHAX /opt/apps/<service>/<données>/ /mnt/nas/apps/<service>/<données>/`.
   Le data directory Postgres peut être copié tel quel, base arrêtée et même
   version majeure.
3. Ajouter la dépendance `nas_storage`, `<service>_data_path`, les bind mounts
   et le borgmatic (voir plus haut). Le data directory Postgres sort de
   `source_directories`.
4. Lancer `docker.yml --tags <service>`, vérifier, faire un premier backup,
   **puis** supprimer l'ancienne copie locale.
