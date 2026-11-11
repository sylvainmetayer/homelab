# L'hôte Proxmox est mort

L'hôte (`pve`, 192.168.1.26, nœud `proxmox`) porte la VM docker (id 100) et
le LXC newt (id 200). Ce site de documentation est sur la VM docker : lire
cette page sur GitHub ou dans un clone local.

## Symptôme

- Toutes les applis de la VM docker tombent (503 ou page de maintenance de
  Pangolin), plus de ping sur 192.168.1.26, 216 et 200.
- Plus d'accès à la maison par le client Pangolin (le Newt du site
  `proxmox-lxc` est dans le LXC), la CI ne déploie plus ni docker ni pi.
- **ntfy, Beszel, VictoriaLogs, Homepage et cette doc sont sur la VM docker :
  les alertes ne viennent plus que de Telegram** (Uptime Kuma est chez PikaPods).

Ne tombent pas : Immich (Newt du Pi), Flip Planning, Pangolin, les sites
Cloudflare Pages. Le DNS dépend de ce que le DHCP de la Bbox annonce
(bascule vers Blocky non constatée au 05/11, [ADR 0012](../adr/0012-filtrage-dns-blocky.md) ;
« À vérifier sur place ») :

- `192.168.1.200` puis `192.168.1.96` : il tient, les clients basculent sur
  le Blocky du Pi ([dns-blocky.md](dns-blocky.md)) ;
- la Bbox elle-même : il tient, sans filtrage ([bbox-remplacee.md](bbox-remplacee.md), étape 3) ;
- `192.168.1.200` seul : il tombe avec le LXC.

## Diagnostic

1. Le courant, le câble, l'écran de la machine (pas d'IPMI). Si elle
   redémarre : [proxmox-injoignable-apres-durcissement.md](proxmox-injoignable-apres-durcissement.md)
   d'abord, ce n'est peut-être qu'un pare-feu.
2. Le disque : le SSD M.2 SATA porte l'hôte et `local-lvm` (`host_vars/pve`).
   Un disque mort = installation neuve. Une carte mère morte avec un disque sain :
   essayer le disque dans une autre machine avant de tout refaire (à vérifier).
3. **Ne restaurer sur un nouvel hôte que si l'ancien ne peut plus se
   rallumer** : deux copies du LXC ou de la VM (même IP, mêmes identifiants
   Newt) se battraient.
4. Le NAS vit-il ? Les archives vzdump y sont (`/volume1/pve-backup`, une
   seule copie, [ADR 0026](../adr/0026-vzdump-sur-le-nas-seul.md)). Sinon : [disque-nas-mort.md](disque-nas-mort.md), et la VM se
   reconstruit depuis Borg (étape C).

## Réparation

### A. Réinstaller l'hôte

1. Proxmox VE depuis l'ISO officielle sur un disque assez grand (VM de 190 Gio,
   `tofu/proxmox/terraform.tfvars`), système de fichiers par défaut : un
   LVM-thin nommé `local-lvm`, que le dépôt attend (`storage = "local-lvm"`
   dans `terraform.tfvars`, `vzdump_restore_test_restore_storage`, commentaire
   de `pve.yml`). Nom du nœud **`proxmox`**,
   IP `192.168.1.26/24`, passerelle `192.168.1.254`.
2. Remettre la configuration de l'ancien hôte depuis Borg (section A bis) :
   elle ramène `authorized_keys`, le certificat ACME de `pve.sylvain.cloud`,
   le jeton de Tofu, le storage `nas-backup` et le job vzdump. Sans archive
   utilisable : mettre les `keys/*.pub` utiles dans
   `/etc/pve/priv/authorized_keys` (console de l'hôte) et refaire le
   certificat (ACME DNS-01 OVH) dans l'interface.
3. **Clé d'hôte** : la lire sur l'hôte (console), jamais par `ssh-keyscan`,
   et remplacer la ligne `pve,…` d'`ansible/known_hosts` par PR
   ([cle-hote-ssh-changee.md](cle-hote-ssh-changee.md)). Les clés des invités
   restaurés ne changent pas.
4. Jeton d'API pour Tofu : revenu avec la configuration (A bis), le
   `PROXMOX_TOKEN` de `secrets/secrets.sops.yaml` marche encore. Sinon en créer
   un ([rotation-des-secrets.md](rotation-des-secrets.md), « Proxmox ») : ses
   droits sont dans le `user.cfg` de l'archive.

### A bis. Remettre la configuration de l'hôte (Borg)

**Jamais essayé** : la sauvegarde existe depuis le 10/11/2026, la
restauration n'a pas été jouée. `/etc/pve` est la vue FUSE de la base
`/var/lib/pve-cluster/config.db` : c'est elle qu'on remet, en entier, sur
l'hôte neuf, avant de restaurer les invités. Dépôt `backup/pve/pve_config`
(rôle `pve_config_backup`, [README](../../ansible/roles/pve_config_backup/README.md)),
une archive par nuit à 01:00.

1. **Depuis le poste**, par le sous-compte en lecture seule `restore-test`
   (clé, utilisateur et serveur : « Diagnostic » de
   [reconstruction-pangolin.md](reconstruction-pangolin.md) ; la clé de
   root de l'ancien hôte est morte avec lui), `BORG_PASSPHRASE` =
   `backup_passphrase` :

   ```bash
   D=ssh://<user>@<server>:23/./pve/pve_config
   cd "$(mktemp -d)"
   borg list --bypass-lock --last 3 "$D"
   borg extract --bypass-lock "$D::<archive>" var/lib/borgmatic-sqlite/pve_config etc
   sqlite3 var/lib/borgmatic-sqlite/pve_config/var_lib_pve-cluster_config.db 'PRAGMA integrity_check'   # ok
   scp var/lib/borgmatic-sqlite/pve_config/var_lib_pve-cluster_config.db root@192.168.1.26:/root/config.db.restaure
   ```

   L'hôte neuf n'a encore que le mot de passe root de l'installation : `scp`
   par mot de passe, ou une clé USB et la console.
2. **Sur l'hôte neuf** (installé avec le nom de nœud `proxmox` : la base
   range tout sous `nodes/proxmox`), sans invité créé :

   ```bash
   systemctl stop pve-cluster
   cp -a /var/lib/pve-cluster/config.db /root/config.db.neuf
   # Un -wal resté là serait rejoué sur la base remise.
   rm -f /var/lib/pve-cluster/config.db-wal /var/lib/pve-cluster/config.db-shm
   install -m 0600 -o root -g root /root/config.db.restaure /var/lib/pve-cluster/config.db
   systemctl start pve-cluster
   ls /etc/pve/storage.cfg /etc/pve/nodes/proxmox
   # Les configs des invités reviennent aussi : sans leurs disques, elles
   # bloqueraient qmrestore/pct restore (et Tofu en route C). De côté.
   mkdir -p /root/invites-anciens
   mv /etc/pve/qemu-server/*.conf /etc/pve/lxc/*.conf /root/invites-anciens/
   pvecm updatecerts
   systemctl restart pvedaemon pveproxy pvestatd pve-firewall
   ```

   Échec (pmxcfs ne démarre pas, interface vide) : remettre
   `/root/config.db.neuf` de la même façon et passer à l'étape A.2 « sans
   archive ».
3. **Ne jamais écraser sur l'hôte neuf** : `/etc/fstab`, `/etc/lvm` et
   `/boot` (propres au disque, absents de l'archive) ; `/etc/network/interfaces`
   de l'archive ne se copie pas tel quel : le nom de la carte réseau change
   d'une machine à l'autre (`ip -br link`). N'en reprendre que ce qui manque
   (adresse et passerelle de `vmbr0`, en gardant le `bridge-ports` de
   l'installeur), puis `ifreload -a`. `/etc/hosts`, `/etc/hostname`,
   `/etc/resolv.conf` : comparer avec ceux de l'installeur, mêmes nom et IP
   attendus.
4. Contrôle : interface web sur `https://192.168.1.26:8006` avec le
   certificat de `pve.sylvain.cloud`, les utilisateurs et le realm
   `pocketid` présents, `pvesm status` montre `nas-backup` (alors
   l'étape B.1 est déjà faite), `cat /etc/pve/jobs.cfg` montre le job vzdump.

### B. Restaurer depuis le NAS

1. Le storage (déjà là si A bis a marché) : `pvesm add nfs nas-backup --server 192.168.1.137 --export
   /volume1/pve-backup --content backup --options vers=3` (valeurs de
   `tofu/proxmox/backup.tf` ; syntaxe de la doc Proxmox, à vérifier). Le NAS
   n'exporte qu'à l'IP 192.168.1.26 : une autre IP demande `nas_nfs_exports`
   et `nas.yml`.
2. Les archives : `ls /mnt/pve/nas-backup/dump/` (`vzdump-lxc-200-*`,
   `vzdump-qemu-100-*`). Prendre les plus récentes dont le `.log` est sans
   `ERROR:`.
3. **Le LXC d'abord** (petit, il rend le DNS redondant et l'accès distant) :

   ```bash
   pct restore 200 /mnt/pve/nas-backup/dump/<archive LXC> --storage local-lvm
   pct start 200
   ```

4. **Puis la VM** (190 Gio de disque : le test bimensuel ne fait que vérifier
   l'archive, la restauration complète n'a **jamais été essayée**, durée à vérifier).
   La VM démarre sur deux fichiers cloud-init `snippets` du storage `local`
   (`user_data_file_id` et `vendor_data_file_id`,
   `tofu/proxmox/proxmox_docker_vm.tf`), absents de vzdump comme de
   l'archive `pve_config` : sur un hôte réinstallé, **`qm start` échoue
   tant qu'ils ne sont pas recréés**. Les recréer d'abord, depuis le poste,
   par un apply ciblé sur ces deux fichiers seulement (un apply complet
   verrait leur id inconnu et remplacerait la VM, `tofu/proxmox/README.md`) :

   ```bash
   tofu -chdir=tofu/proxmox apply \
     -target=proxmox_virtual_environment_file.docker_user_config \
     -target=proxmox_virtual_environment_file.docker_vendor_config
   ```

   Le storage `local` doit accepter le contenu `snippets` : A bis le remet
   avec `storage.cfg` ; sans A bis, si l'apply échoue sur le type de
   contenu, l'ajouter au storage `local` (Datacenter → Storage) puis
   relancer (comportement non décrit dans le dépôt). Ensuite :

   ```bash
   qmrestore /mnt/pve/nas-backup/dump/<archive VM> 100 --storage local-lvm
   qm config 100 | grep -E 'cicustom|ide|net0|onboot'
   qm start 100
   ```

5. L'archive date de 21:00 au plus tard la veille : les données écrites depuis
   n'y sont pas. Pour une appli importante, remettre ensuite son dump Borg de
   01:00 ([sauvegarde-et-restauration.md](sauvegarde-et-restauration.md)).

### C. NAS aussi perdu, ou VM douteuse

Pas d'archive : recréer la VM par Tofu (`mise run init-proxmox`, `plan-proxmox`,
relire, `apply-proxmox`), puis `ansible-playbook docker.yml` et chaque appli
depuis Borg, une à une (`backup/docker/<app>`). Long : tout est hors site, rien
n'est perdu, mais rien n'est rapide. Tofu ne fixe pas l'id de la VM :
`proxmox_docker_vm.tf` ne lit pas `vm_id` (le `300` de `terraform.tfvars`
n'est lu par aucune ressource), la VM d'origine a reçu le 100 à sa création
(`ansible/roles/vzdump_restore_test/defaults/main.yml`). Après l'apply,
`qm list` doit donner 100 ; sinon `vzdump_restore_test_vm_source` et les
commandes de cette page sont à adapter. Même chose si la VM est suspecte
([intrusion-premiere-heure.md](intrusion-premiere-heure.md)) : une archive
restaurée ramène aussi l'intrus.

Une fois les données de chaque appli restaurées, **second passage**
`ansible-playbook docker.yml --tags backup` (même chose pour `pi.yml` et
`nas.yml`) : Ansible ne repère une base SQLite que si le fichier existe, donc
sans ce passage les configs borgmatic copient les bases vivantes à chaud
chaque nuit. Vérifier que l'archive suivante contient
`var/lib/borgmatic-sqlite`.

### D. Remettre Tofu et Ansible d'accord

1. `tofu -chdir=tofu/proxmox plan` : stockage `nas-backup` (déjà créé) et
   job vzdump à recréer (rien à faire pour les deux si A bis les a remis : à
   vérifier), jamais un `must be replaced` sur la VM ou le LXC (les
   invités restaurés sont retrouvés par leur id). Le storage créé à la main
   s'importe par la CLI (`tofu import`, identifiant à vérifier dans la doc du
   provider). Le job a un id fixe : si l'apply le refuse comme déjà pris
   (remis par A bis), `tofu -chdir=tofu/proxmox import
   proxmox_backup_job.nightly backup-cbfcde61-8413` (commande de `tofu/proxmox/backup.tf`).
2. Depuis `ansible/`, avec `--check --diff` d'abord :
   `ansible-playbook pve.yml` (dans cet ordre : sauvegarde de la
   configuration, agent Beszel, test de restauration, avis de mises à jour,
   `smart_check`, `thin_pool_check`, `pve_hardening` (une session root de
   secours ouverte), puis la tâche `/etc/vzdump.conf`), et `lxc.yml` (à la main) si le LXC doit être
   remis d'équerre. La sauvegarde de la configuration repart avec une clé
   neuve : `ansible-playbook pve.yml --tags setup`, puis `backup.yaml`, puis
   `pve.yml` complet (sinon le `repo-create` de `pve_config_backup` est refusé
   par le sous-compte).

## Vérification

- `qm list` et `pct list` : 100 et 200 `running` ; `pvesm status` :
  `nas-backup` actif.
- Sur le LXC : `systemctl status newt blocky` ; le site `proxmox-lxc` est en
  ligne dans Pangolin ; `dig +short @192.168.1.200 example.com` répond.
- Sur la VM : `systemctl --user list-units 'dc@*' --state=failed` vide ;
  moniteurs Uptime Kuma verts ; ntfy reçoit un message.
- Une sauvegarde à la main (`vzdump 100 200 --storage nas-backup --mode
  snapshot --compress zstd`) réussit, et le prochain run de 21:00 aussi.
- Après 01:00, le moniteur « Backup Proxmox config » est vert
  (`tofu/pangolin_config/backup_pve_config.tf`) : la configuration de l'hôte
  neuf est de nouveau sauvegardée.
- Un merge de test qui déploie passe (la CI joint la maison par le LXC).

## Prévention

- Ne garder qu'une copie des archives sur le NAS est un risque accepté (ADR 0026).
- Droits du jeton Proxmox et configuration de l'ACME : dans l'archive Borg
  `pve_config` (A bis), pas encore écrits dans le dépôt.
- Jouer A bis une fois sur un Proxmox jetable (VM imbriquée) : jamais fait.
- Une restauration complète de la VM, essayée une fois, vaut mieux qu'une
  archive seulement vérifiée ([test-restauration-vm.md](test-restauration-vm.md)).

## À vérifier sur place

Sur l'hôte actuel, tant qu'il marche : ce que la réparation suppose et que le
dépôt ne dit pas.

- **Shell de l'hôte** : `pvesm status` liste `local` avec le contenu
  `snippets` (ce que l'apply ciblé de B.4 suppose sans A bis).
- **BIOS du mini PC** : « Restore on AC Power Loss », attendu « Power On »
  ou « Last State », pas « Off »
  ([coupure-de-courant.md](coupure-de-courant.md)) ; à reporter sur une
  machine neuve.
- **Interface de la Bbox** : les DNS annoncés par le DHCP, attendus
  `192.168.1.200` puis `192.168.1.96` ; lequel des trois cas du Symptôme
  s'applique ([bbox-remplacee.md](bbox-remplacee.md)).
- **Uptime Kuma** : « Backup Proxmox config » vert chaque matin depuis le
  10/11 ; depuis le poste, `borg list --bypass-lock --last 3` de A bis
  (étape 1) liste des archives récentes.

**Relevé du 11/11/2026** (lecture seule, en SSH sur l'hôte) :

- `pvesm status` : `local` (dir, actif, contenu `snippets,vztmpl,backup,iso`),
  `local-lvm` (lvmthin, actif), `nas-backup` (nfs, actif). L'apply ciblé de
  B.4 trouve donc bien `snippets` sur `local`.
- Identifiants : la VM docker a le VMID **100**, le LXC newt le **200**
  (`qm list`, `pct list`), pve-manager 9.2.26.
- Réseau : `vmbr0` en IP fixe `192.168.1.26/24`, passerelle `192.168.1.254`
  (`/etc/network/interfaces`).
- Timers : `borgmatic.timer` (01:00, dernier passage la nuit du 11/11),
  `vzdump-freshness.timer` (07:30), `vzdump-restore-test.timer` (lundi 10:00).

Restent à voir sur place : le BIOS (« Restore on AC Power Loss »), les DNS
annoncés par la Bbox, le moniteur « Backup Proxmox config ».
