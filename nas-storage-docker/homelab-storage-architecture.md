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
| Fichiers (uploads, médias, données de l'appli) | NAS | NFSv3, export monté sur la VM (`/mnt/nas/apps`), bind mount dans le conteneur | copie des fichiers |
| BDD serveur (Postgres, MariaDB) | NAS | même export, sous-dossier de l'appli | **dump logique** (`borgmatic_app_postgresql_databases` / `_mysql_databases`), jamais la copie du data directory |
| BDD embarquée (SQLite, LMDB, BoltDB…) | disque local de la VM | bind mount sous `/opt/apps/<service>` comme aujourd'hui | `borgmatic_app_sqlite_databases` (copie `sqlite3 .backup`, jamais le `sqlite_databases` de borgmatic) ou fichiers |
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

### NFSv3, faute de mieux

NFSv4.1 aurait été préférable (verrous dans le protocole, un seul port
2049/tcp), mais **UGOS Pro 1.20 ne sert que NFSv3** : « Max protocole NFS »
(Panneau de configuration → Service de fichiers → NFS → Paramètres avancés)
ne propose que NFSv3, avec la mention « Gamme NFS : NFSv3, NFSv2 ». knfsd répond
bien en v4 au niveau RPC (`rpcinfo -t 192.168.1.137 nfs 4`), mais aucun
pseudo-système de fichiers v4 n'est exporté : un montage `vers=4`, `4.1` ou
`4.2` échoue avec « reason given by server: No such file or directory », y compris sur `/`
(testé depuis le Pi le 2026-10-25). Le rôle monte donc en `vers=3`.

Une seule source, non officielle (un blog, sur un DH2300), dit qu'on peut
activer la v4 en SSH en éditant `/etc/nfs.conf` et `/etc/nfs.json` du NAS. Elle
prévient qu'un « Enregistrer » dans l'interface remet la v3. Ugreen considère
toute modification du système comme non supportée. Rien ne garantit que ces
réglages survivent à une mise à jour d'UGOS : la v4.1 reste donc hors du
chemin par défaut. Si on la met en place, passer `nas_storage_nfs_version:
"4.1"` et revérifier le mapping d'identités (`ls -ln` : pas de `4294967294`).

Conséquences de la v3 :

- les verrous passent par NLM (`lockd` côté noyau, `rpc-statd`, démarré
  automatiquement par `mount.nfs`) ; `local_lock=none`, ils sont donc vus par
  le NAS ;
- `mountd`, `statd` et `nlockmgr` utilisent des ports dynamiques côté NAS
  (ports fixables dans les Paramètres avancés NFS d'UGOS) ;
- **non testé** : le NAS rappelle le client (callback `GRANTED` d'un verrou
  bloquant, `SM_NOTIFY` après un redémarrage du NAS pour reprendre les
  verrous). La VM refuse tout entrant hors 22/80/443 (rôle `security`), donc
  ces rappels sont perdus. Postgres ne s'appuie pas sur les verrous fcntl pour
  ses fichiers de données. À vérifier avant d'y mettre une appli qui verrouille
  ses fichiers.

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
- Déclare l'export dans `/etc/fstab` : `vers=3,hard,proto=tcp,noatime,_netdev,nofail,x-systemd.automount,x-systemd.mount-timeout=30`,
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
(`"3"` : passer à `"4.1"` le jour où UGOS exporte en v4, voir plus haut).

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
   `ExecStartPre=/usr/local/bin/nas-storage-wait 150`. Au boot, la VM est
   prête avant le NAS ; sans attente, chaque `docker compose up` bute sur
   l'automount (30 s) et échoue sur une erreur de bind mount de Docker. `dc@`
   réessaie sans fin (`StartLimitIntervalSec=0`), l'attente remplace ces
   échecs par un message clair. Les `ExecStartPre` partagent le
   `TimeoutStartSec` de 300 s de `dc@` : attente de Docker (120 s au plus),
   pull, puis celle du NAS.
5. Borgmatic (rôle `borgmatic`, `tasks_from: app.yml`, comme toutes les
   applis) :
   - les dossiers de fichiers du NAS dans `borgmatic_app_source_directories`,
     **sans** le data directory de la base, qui passe par
     `borgmatic_app_postgresql_databases` / `borgmatic_app_mysql_databases`
     (dump par le client du conteneur de la base) ;
   - `source_directories_must_exist: true`, via `borgmatic_app_extra_options` ;
   - `nas-storage-wait 30` dans `borgmatic_app_before_commands`, lancé avant
     que borg ne lise le NAS. Il n'y a
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

Libellés d'UGOS Pro 1.20.0.0142, relevés le 2026-10-25 (test du dossier
`nas-test` depuis le Pi).

1. **Service NFS** : Panneau de configuration → Service de fichiers → onglet
   NFS → « Activer le service NFS ». Dans « Paramètres avancés », « Max
   protocole NFS » ne propose que **NFSv3**. La valeur est dans
   `/etc/nfs.json` (`maximumNFSProtocol`), dont `conf_tool` régénère
   `/etc/nfs.conf` à chaque démarrage de nfs-server ; le rôle `nas` l'épingle.
   NFSv4.1 y est accepté mais inutilisable : aucune pseudo-racine v4.
2. **Dossier partagé** : Fichiers → Dossier partagé → « Créer un dossier
   partagé », nom `apps`, emplacement Volume 1. Décocher « Activer la
   corbeille » : sinon UGOS crée `#recycle` (0777) à la racine du partage
   (la corbeille ne sert qu'à SMB : une suppression par NFS est définitive).
   La fenêtre « Autorisations des dossiers partagés » qui suit ne concerne
   que les comptes UGOS (SMB, interface) : la laisser par défaut
   (Administrateur en lecture/écriture).
3. **Export NFS** : publié par `ansible-playbook nas.yml` (rôle `nas`,
   `host_vars/nas`), pas dans l'interface. Le rôle écrit
   `/etc/exports.d/homelab.exports` (UGOS garde `/etc/exports` pour les règles
   de l'interface et nfs-server relit les deux) avec les options qu'UGOS
   donne à « Lecture/écriture, Aucun mappage », mais en `sync` : l'interface
   coche « Async » par défaut. « Aucun mappage » (`no_root_squash`) est
   nécessaire pour que borg (root sur la VM) lise tout et que l'entrypoint
   Postgres fasse `chown` de son data directory ; le risque est contenu
   parce que l'export ne vise que l'IP de la VM. Le rôle vérifie aussi que
   le dossier existe, que nfs-server tourne et qu'aucun export n'est `async`.
   Il est lancé à la main, jamais par la CI.
4. Chemin exporté : `/volume1/nas-test` aujourd'hui (défaut de
   `nas_storage_export`, dossier de l'essai du 25/10). Depuis la VM,
   `showmount -e 192.168.1.137` doit lister `/volume1/nas-test 192.168.1.216`.
5. Premier test depuis la VM :
   ```bash
   sudo mount -t nfs -o vers=3,hard 192.168.1.137:/volume1/nas-test /mnt && nfsstat -m && ls -lan /mnt && sudo umount /mnt
   ```
   En v3 (`sec=sys`), les UID/GID passent tels quels : pas de mapping par nom.
6. (Recommandé) Snapshots Btrfs planifiés sur `apps`, en complément de borg.

Pare-feu du NAS (UGOS, chaîne nftables `UG_INPUT`) : la règle « NFS » de
l'interface n'ouvre que 111, 2049 et les ports **dynamiques** de `mountd`,
`statd` et `nlockmgr` relevés au moment où UGOS a écrit ses règles. Un
redémarrage de nfs-server hors de l'interface (handler du rôle `nas`)
déplace ces ports : `showmount` et le montage restent alors bloqués alors que
111 et 2049 répondent (constaté le 26/10). D'où une règle « tout autoriser »
pour chaque client NFS (VM `192.168.1.216`, Pi `192.168.1.96`) dans
Sécurité → Pare-feu.

### Applis lancées sur le NAS lui-même (`dc@` système)

Quelques applis tournent sur le NAS plutôt que sur la VM (Beszel, Jellyfin
à venir), avec le Docker qu'installe l'appli Docker d'UGOS (Docker 29,
`data-root` `/volume1/@docker`). Elles suivent le même modèle `dc@<service>`
que les autres hôtes, mais en **unité système** exécutée en root
(`docker_service_scope: system` dans `host_vars/nas`,
`/etc/systemd/system/dc@.service`, posée par `nas.yml`, tags `setup` et `always`) :
sylvain n'est pas dans le groupe docker, `/etc/group` appartient à UGOS, et
il n'y a pas de lingering à gérer.

- Composes sous `/volume1/docker/<service>` (`docker_base_path`), dossier
  partagé `docker` créé par l'appli Docker d'UGOS ; il est partagé en SMB au
  groupe `admin`, d'où un dossier 0700 root par appli. Avec `skip smb perm`,
  un compte admin en SMB pourrait quand même lire ou modifier ces composes
  (secrets, conteneurs lancés en root) : risque accepté. UGOS présente à root
  des modes de dossiers partagés différents de ceux qu'il montre à sylvain
  (`d---------` pour `nas-test`, `drwx------` pour `docker`, `drwxrwxrwx`
  côté sylvain) : ne pas s'y fier pour diagnostiquer.
- `docker.service` y est désactivé : `docker_serv` (UGOS, après le montage
  des volumes) active `docker.socket`, et le démon démarre à la première
  requête. `dc@` est donc rangé `After=docker_serv.service docker.service`
  sans les tirer (un `Requires=` démarrerait Docker avant `/volume1`), et
  attend `docker info` comme ailleurs. `docker_serv` étant `Before=`
  `multi-user.target`, pas de cycle ; en revanche `multi-user.target` attend
  les `ExecStartPre` de chaque `dc@` activé (attente de Docker, images
  absentes) : 300 s par essai (`TimeoutStartSec`), mais jusqu'à
  `JobRunningTimeoutSec` (10 min) si Docker ne vient pas, `Restart=always`
  gardant le job de démarrage ouvert d'un essai à l'autre. Pas encore vérifié par un
  redémarrage du NAS.
- La racine est un overlay sur l'eMMC (`/overlay/upper`) : l'unité survit aux
  redémarrages, peut-être pas à une réinitialisation d'UGOS. Relancer
  `nas.yml`, qui repose et revérifie tout.

### Comportements observés (test depuis le Pi, 2026-10-25)

- **Les droits demandés à la création sont ignorés** : tout fichier ou dossier
  créé par NFS sort en `0777`, même sous `umask 077` (ACL d'UGOS). Un
  `chmod`/`chown` explicite, lui, est respecté et persiste (`0750 101:101`,
  `0640` vérifiés). Les modes du rôle `nginx_demo` (module `file`/`copy` avec
  `mode:`) tiennent donc, mais **tout ce qu'une appli crée elle-même** sur le
  NAS est lisible et modifiable par tous les clients NFS autorisés et par les
  comptes UGOS qui ont accès au dossier. L'entrypoint Postgres fait un
  `chmod 0700` de `PGDATA` ; les fichiers créés dedans sont en `0777` sur le
  NAS, mais ils sont inaccessibles par traversée du dossier.
- **Automount** (`systemd-mount --automount=yes`, l'équivalent transitoire de
  `x-systemd.automount`) : un `docker compose start` alors que le `.mount` est
  arrêté déclenche le montage, et le bind mount pointe bien sur le NFS.
- **Coupure du NAS de 60 s** (`iptables -I OUTPUT -d 192.168.1.137 -j DROP`) :
  les workers nginx passent en état `D`, `curl` expire, `stat -f` et `ls`
  bloquent mais meurent par `SIGKILL` (la sonde de `nas-storage-wait` est
  valide). `docker ps` et `docker inspect` répondent, les autres conteneurs
  (Immich) ne sont pas touchés. Au retour, reprise en moins de 2 s, sans
  redémarrage du conteneur. Le healthcheck revient à `healthy`. Rien dans
  `dmesg` : avec `timeo=600`, le noyau ne signale « server not responding »
  qu'après plusieurs minutes.


## Déployer l'appli pilote

```bash
cd tofu/pangolin_config && tofu plan && tofu apply   # route + monitors nginx-demo
cd ../../ansible
ansible-playbook docker.yml --check --tags nginx_demo   # borg crée seul le dépôt (sous-compte de docker)
ansible-playbook docker.yml --tags nginx_demo
```

Vérifier :

```bash
findmnt /mnt/nas/apps                                  # nfs, vers=3, hard
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
