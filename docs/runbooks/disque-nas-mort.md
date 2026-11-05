# Un disque du NAS meurt, ou le NAS entier

Le NAS Ugreen (UGOS Pro, 192.168.1.137) range ses données sur un volume en
RAID 1 (`/volume1`, 3,7 To d'après `tofu/proxmox/backup.tf`).
Un RAID 1 n'est pas une sauvegarde : un disque mort se remplace, deux disques
(ou le boîtier) morts font perdre ce qui n'a pas de copie ailleurs.

Les noms de menus d'UGOS et le matériel ne sont pas décrits dans le dépôt :
tout ce qui touche l'interface d'UGOS est marqué « à vérifier ».

## Symptôme

- Alerte du RAID dans UGOS (volume « dégradé », « défaillant » : intitulé à
  vérifier), page S.M.A.R.T. de `nas` dans Beszel rouge (disques `sda`, `sdb`,
  `sdc` suivis, `host_vars/nas`).
- Ou le NAS ne répond plus : moniteurs « Healthcheck Jellyfin », « Certificats
  NAS », « kDrive vers NAS » et « Backup Jellyfin » rouges ensemble, agent
  Beszel `nas` hors ligne.

## Ce qui dépend du NAS

| Dépend du NAS | Si le NAS manque | Copie ailleurs |
|---|---|---|
| Archives vzdump (VM docker, LXC newt), `/volume1/pve-backup` | le job de 21:00 échoue ; **plus aucune image** des deux invités | aucune ([ADR 0026](../adr/0026-vzdump-sur-le-nas-seul.md)) ; Borg garde les applis |
| Jellyfin : configuration et base | Jellyfin et `media.sylvain.cloud` tombent | Borg, `backup/nas/jellyfin` |
| Médias (`/volume1/media`) | perdus avec les deux disques | **aucune dans le dépôt** : Borg ne les prend pas, le miroir kDrive exclut films et séries ; instantanés d'UGOS sur les mêmes disques. Copie éventuelle ailleurs : à vérifier |
| Copie de kDrive (`/volume1/kdrive`) | le miroir et `versions/` disparaissent | kDrive lui-même (hors films et séries exclus, `host_vars/nas`) |
| MediaManager (essai) | tombe | configuration dans Borg ; **base PostgreSQL jamais sauvegardée** ([README du rôle](../../ansible/roles/mediamanager/README.md)) |
| Traefik du NAS (`nas_proxy`), Newt du site `nas` | `media.`, `nas.` et `mediamanager.sylvain.cloud` tombent | rien à sauver : certificats redemandés, identifiants Newt dans le state de `pangolin_config` |
| Borgmatic du NAS (02:30) | plus de sauvegarde Jellyfin | clé et configs sous `/volume1/docker/borgmatic`, refaites par `nas.yml` |

Ne dépendent pas du NAS : la VM docker, le LXC newt, le Pi, Pangolin, flip
(aucune appli n'utilise le rôle `nas_storage` aujourd'hui).

## Diagnostic

1. Un disque ou deux ? Dans UGOS (gestionnaire de stockage, à vérifier) et
   dans Beszel. Noter le **numéro de série** du disque fautif : c'est lui
   qu'on retire, pas le voisin. D'après `host_vars/nas`, `sda` et `sdb`
   (4 To) sont la paire du RAID (`md1` en raid1 sur `sda2` et `sdb2`, relevé du
   05/11 : `cat /proc/mdstat` donne `[UU]`, et `[U_]` ou `[_U]` si un disque
   manque), `sdc` est un disque USB, hors RAID.
2. Le disque restant est-il sain ? Son S.M.A.R.T. avant tout (Beszel). S'il
   est douteux, copier d'abord ce qui compte (Réparation, étape 1).
3. Les sauvegardes sont à jour : moniteurs « Backup Jellyfin » et « kDrive
   vers NAS » verts avant la panne.

## Réparation

### A. Un disque mort, le volume est dégradé

1. **Pendant la reconstruction, le disque restant est seul.** Copier les
   deux dernières archives vzdump vers le poste si la place le permet
   (`/mnt/pve/nas-backup/dump/` sur l'hôte Proxmox, ~50 Gio pour la VM). Ne
   pas lancer de nouveau vzdump pour cela : `keep-last=2` ferait élaguer la
   plus ancienne.
2. Remplacer le disque (même capacité ou plus, modèle pour NAS ; le modèle
   actuel est dans `host_vars/nas`). Échange à chaud ou NAS éteint : à vérifier
   dans la notice du boîtier.
3. Lancer la réparation du volume dans UGOS (assistant : à vérifier). Compter
   des heures. Les tâches de 21:00 (vzdump), 02:30 (borgmatic) et 04:00
   (kDrive) ralentissent la reconstruction et en sont ralenties ; un échec
   isolé de l'une d'elles pendant ce temps n'est pas grave.
4. Rien à rejouer sur Ansible si les données sont revenues. Si UGOS a
   été touché, `ansible-playbook nas.yml --check --diff`
   ([mises-a-jour-hotes.md](mises-a-jour-hotes.md), « Après »).

### B. Les deux disques, ou le NAS entier

1. **Constater ce qui est perdu** avec le tableau ci-dessus. Si les disques
   sont sains et seul le boîtier est mort : essayer de les monter dans un
   boîtier Ugreen identique (reprise du RAID par UGOS : à vérifier chez
   Ugreen) avant de les formater.
2. **NAS neuf, dans UGOS** : IP `192.168.1.137` (réservation de la Bbox ou IP
   fixe d'UGOS : à vérifier, [bbox-remplacee.md](bbox-remplacee.md)), compte
   `sylvain` avec la clé SSH, volume RAID 1, application Docker d'UGOS (elle
   crée le dossier partagé `docker`), puis les dossiers partagés `media`,
   `kdrive` (instantanés activés), `pve-backup` (corbeille décochée, ni SMB ni
   autre utilisateur). Détails : [README de nas_storage](../../ansible/roles/nas_storage/README.md),
   [kdrive-nas.md](kdrive-nas.md), [sauvegarde-et-restauration.md](sauvegarde-et-restauration.md).
   Autre IP : `grep -rn 192.168.1.137` dans le dépôt (DNS `tofu/dns`,
   ressources privées de `pangolin_config`, `nas_backup` de `tofu/proxmox`,
   `known_hosts`, Blocky), à changer partout.
3. **Clé d'hôte** : la relever sur le NAS par un canal sûr (écran branché ou
   terminal d'UGOS : à vérifier), jamais par `ssh-keyscan`, puis remplacer la
   ligne `nas` d'`ansible/known_hosts` par PR
   ([cle-hote-ssh-changee.md](cle-hote-ssh-changee.md)).
4. **Dans l'ordre**, depuis `ansible/`, toujours `--check --diff` d'abord :

   ```bash
   ansible-playbook nas.yml --tags setup   # dc@, borgmatic, clé SSH du NAS
   ansible-playbook backup.yaml            # l'autorise chez backup-nas
   ansible-playbook nas.yml                # le reste, export pve-backup compris
   ```

   Jellyfin démarre à vide : c'est sans conséquence tant qu'on l'arrête avant
   l'étape 5.
5. **Jellyfin depuis Borg** : `sudo systemctl stop dc@jellyfin` (unité
   système sur le NAS), extraire avec l'enrobage
   `/volume1/docker/borgmatic/borgmatic --config
   /volume1/docker/borgmatic/borgmatic.d/jellyfin.yaml extract --archive latest
   --destination /volume1/docker/borgmatic/restore`, recopier `config/` sous
   `/volume1/docker/jellyfin/`, remettre les copies SQLite
   (`find /volume1/docker/borgmatic/restore -name '*.db'` : emplacement en
   mode conteneur à vérifier, procédure SQLite dans
   [sauvegarde-et-restauration.md](sauvegarde-et-restauration.md)), redémarrer.
   Médias : à remettre depuis la copie que Sylvain aura (à vérifier).
6. **vzdump** : sur l'hôte Proxmox, `pvesm status` doit montrer `nas-backup`
   actif (un montage resté bloqué se reprend quand le NAS répond : à vérifier).
   Tant qu'aucune archive n'existe, **les invités n'ont aucune image** : lancer
   tout de suite
   `vzdump 100 200 --storage nas-backup --mode snapshot --compress zstd`.
7. **kDrive** : la première copie se refait à la main
   ([kdrive-nas.md](kdrive-nas.md), `kdrive_sync_timer_enabled`). L'historique
   `versions/` est perdu.
8. **MediaManager** repart d'une base vide ; la clé WireGuard vient de SOPS
   (`mediamanager_wireguard_private_key`). Voir
   [mediamanager-nas.md](mediamanager-nas.md).

## Vérification

- `https://media.sylvain.cloud` et `https://nas.sylvain.cloud` répondent ;
  moniteurs « Healthcheck Jellyfin », « Certificats NAS » (le certificat est
  redemandé par DNS-01 : limites de Let's Encrypt à vérifier si on enchaîne les
  essais), « Backup Jellyfin » (après 02:30), « kDrive vers NAS » verts.
- Depuis l'hôte Proxmox : `showmount -e 192.168.1.137` liste
  `/volume1/pve-backup 192.168.1.26`, et une archive neuve est dans
  `/mnt/pve/nas-backup/dump/`.
- Agent Beszel `nas` en ligne, S.M.A.R.T. lisible.

## Prévention

- Surveiller le S.M.A.R.T. de `nas` dans Beszel ; remplacer un disque qui
  se dégrade avant qu'il meure. Beszel ne voit que le verdict global, pas les
  secteurs en attente : contrôle trimestriel et scrub Btrfs dans
  [sante-des-disques.md](sante-des-disques.md).
- Le point faible reste ADR 0026 : les archives vzdump n'existent que sur ce
  NAS. Une copie hors du NAS (même du seul LXC, qui est petit) réduit le trou.
- Les médias n'ont qu'une copie : décider d'une sauvegarde ou l'assumer.
- Ce site de documentation tourne sur la VM docker : si elle est touchée, lire
  ce fichier sur GitHub ou dans un clone local.
