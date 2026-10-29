# Test de restauration des sauvegardes vzdump (VM docker, LXC newt)

Le job vzdump de Proxmox (`tofu/proxmox/backup.tf`, 21:00) sauvegarde la VM
docker (id 100) et le LXC newt (200) sur le storage `nas-backup`. Une
sauvegarde qui n'a jamais été restaurée n'en est pas une : le 2 et le 16 de
chaque mois à 10:00, `vzdump-restore-test.timer` (rôle `vzdump_restore_test`,
`ansible/pve.yml`) lance sur l'hôte même
`/usr/local/lib/vzdump-restore-test/vzdump_restore_test.py` :

- **LXC newt** : la dernière sauvegarde (moins de 26 h, au moins 100 Mio, son
  journal vzdump sans `ERROR:`) est restaurée sur l'id **990**, sur
  `local-lvm`, avec `--onboot 0` et ses interfaces réseau débranchées
  (`link_down=1`), puis supprimées avant tout démarrage. Hors ligne
  (`pct mount`) : `/etc/hostname` vaut celui de l'archive, l'unité, les
  identifiants et le binaire de newt sont là, puis `newt.service` est
  masqué dans la copie. Démarrage : aucune interface autre que `lo`, systemd
  doit atteindre `running` ou `degraded` (sans réseau, `networking.service`
  échoue : attendu, listé dans le rapport). Puis arrêt et destruction.
- **VM docker** : la dernière sauvegarde (moins de 26 h, au moins 10 Gio,
  journal sans erreur) est entièrement décompressée et vérifiée
  (`zstd -d -c … | vma verify -` : somme zstd de chaque trame, structure VMA
  de chaque disque), une dizaine de minutes de lecture sur le NFS. Pas de
  restauration : 190 Gio de disque virtuel (~105 Gio écrits sur le SSD des
  invités) et une mémoire que l'hôte n'a pas (15 Gio, dont 12 à la VM docker).

Le résultat part sur **ntfy** (topic `scripts`, priorité haute sur échec,
basse sinon) avec le détail, et au moniteur
push **« Test restauration vzdump »** d'Uptime Kuma
(`tofu/pangolin_config/cron_vzdump_restore_test.tf`, 20 jours : le provider
plafonne un push à 24 jours, d'où deux runs par mois). Le moniteur passe
aussi au rouge si plus rien n'arrive (hôte éteint à 10:00, timer mort).

Garde-fous du script :

- l'id cible est dans 900-999 (réservés à ce test : n'y créer aucun
  invité), différent des sources, et le run échoue s'il existe ou si
  `local-lvm` porte un volume orphelin à son nom ;
- jamais de `--force` ; `pct destroy` avec
  `--destroy-unreferenced-disks 0`, et seulement sur un invité créé par ce
  run **et** dont la description porte `vzdump-restore-test` ;
- aucune copie ne démarre avec une interface réseau, `onboot` actif, sans
  la marque, ou avec un accès direct à l'hôte (montage lié `mpN: /…`,
  disque en passthrough `/dev/…`, `hostpciN`, `usbN`, `devN`, `args`,
  lignes brutes `lxc.*`) : elle serait branchée sur ce qu'utilise l'invité
  de production ;
- un verrou (`/run/lock/vzdump-restore-test.lock`) et celui de vzdump
  (`/var/run/vzdump.lock`), tenu pendant tout le test : pas de sauvegarde
  ni d'élagage de l'archive pendant sa lecture (un vzdump lancé à la main
  pendant le test attend) ;
- chaque étape a son délai ; le `TimeoutStartSec` de l'unité (3 h 05) les
  borne tous. Dépassé, systemd envoie SIGTERM au script seul
  (`KillMode=mixed`), qui tue la commande en cours et détruit ses copies
  avant de rapporter.

## Symptôme

- Notification ntfy « Test de restauration vzdump : ÉCHEC », ou moniteur
  « Test restauration vzdump » rouge.
- Un invité 990 visible dans l'interface de Proxmox en dehors du 2 et
  du 16 au matin.

## Diagnostic

Depuis le poste, en root sur l'hôte (`ssh root@192.168.1.26`) :

```bash
journalctl -u vzdump-restore-test.service -n 200 --no-pager   # chaque commande lancée, sa sortie
systemctl list-timers vzdump-restore-test.timer
pvesm status                                                  # nas-backup actif ? place sur local-lvm ?
pvesh get /nodes/proxmox/storage/nas-backup/content --content backup --output-format json-pretty
ls -la /mnt/pve/nas-backup/dump/
pct list                                                      # une copie 990 restée ?
```

Selon la première ligne `ÉCHEC :` du rapport :

- **« plus vieille que 26 h »**, **« aucune sauvegarde »**, **« le journal de
  la sauvegarde signale une erreur »** : c'est le job vzdump qui a échoué,
  pas le test. Voir [sauvegarde-et-restauration.md](sauvegarde-et-restauration.md),
  « Sauvegarde vzdump de Proxmox » (storage NFS absent, `tmpdir`, place).
- **« vma : code 1 sur l'archive »** ou **« zstd : code … »** : l'archive est
  corrompue (ou le NFS a coupé pendant la lecture). Relancer le test ; si
  l'échec revient sur l'archive suivante, vérifier le NAS (disques, RAID,
  `dmesg` de l'hôte pour des erreurs NFS) et lancer une sauvegarde à la main.
- **« id cible 990 déjà pris »**, **« volumes orphelins »** : une copie
  d'un run précédent (tué par SIGKILL, hôte redémarré pendant le test) ou un
  invité créé à la main dans 900-999. Voir Réparation.
- **« systemd à l'état … »** : la copie ne démarre pas. Démarrer la vraie
  machine n'est pas en cause ; lire `pct console 990` en relançant le test à
  la main
  (voir Vérification) avant qu'il ne détruise la copie, ou restaurer à la
  main sur un id de test pour regarder.
- **« verrou … déjà pris »** : un autre test ou un vzdump tournait.
- **« nettoyage de 990 : … »** : la copie n'a pas pu être détruite, elle est
  encore là. Voir Réparation.

## Réparation

Une copie restée (990) se détruit à la main, après avoir vérifié que c'est
bien elle :

```bash
pct config 990 | grep -i description   # doit contenir vzdump-restore-test
pct stop 990; pct destroy 990 --destroy-unreferenced-disks 0
```

Jamais sur un autre id, jamais `--purge` d'un id de production. Un volume
orphelin (`pvesm list local-lvm --vmid 990`) sans invité : `pvesm free
local-lvm:vm-990-disk-0`, après avoir relu son nom.

## Vérification

Relancer le test à la main (une demi-heure environ, l'interface de Proxmox
montre la restauration du LXC puis la lecture de l'archive) :

```bash
systemctl start vzdump-restore-test.service   # rend la main à la fin ; code non nul sur échec
journalctl -u vzdump-restore-test.service -n 50 --no-pager
pct list                                       # pas de 990
```

Le moniteur passe au vert, ntfy reçoit « OK ».

## Prévention

- Ne créer aucun invité dans 900-999.
- Le job vzdump et ce test lisent les mêmes ids (100, 200) : un invité ajouté
  au job sans entrée ici n'est pas testé ; un id changé (VM recréée) fait
  échouer le test sur « aucune sauvegarde » jusqu'à la mise à jour de
  `vzdump_restore_test_*_source` (`ansible/roles/vzdump_restore_test/defaults/main.yml`).
- Les tailles plancher (100 Mio, 10 Gio) sont celles du 27/10/2026 divisées
  par trois : à revoir si la VM docker change de taille.
