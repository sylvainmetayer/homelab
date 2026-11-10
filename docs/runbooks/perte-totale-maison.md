# Perte totale de la maison

Le NAS, l'hôte Proxmox, le Pi et le poste de Sylvain disparaissent ensemble
(incendie, inondation, vol, surtension) : le scénario « maison sinistrée » de
la [matrice des données](../matrice-des-donnees.md). Cette page est le fil qui
relie les runbooks d'un seul hôte ([hote-proxmox-mort.md](hote-proxmox-mort.md),
[disque-nas-mort.md](disque-nas-mort.md), [pi-mort.md](pi-mort.md),
[bbox-remplacee.md](bbox-remplacee.md), [perte-cle-ou-poste.md](perte-cle-ou-poste.md)) :
elle ne les répète pas, elle donne l'**ordre** et le **critère** pour passer à
l'étage suivant.

Rien n'a été rejoué de bout en bout. Les durées viennent de la matrice
(estimations, sauf Pangolin : 45 min mesurées). Ce que le dépôt ne dit pas est
marqué « à vérifier ». Le dépôt est public : aucun lieu de rangement, aucune
valeur de secret n'est écrit ici ; ils se notent hors du dépôt (« Prévention »).

## Symptôme

Plus de réseau local, plus d'hôte Proxmox, de Pi ni de NAS, et plus de poste
pour agir. De l'extérieur : `photos.sylvain.cloud` et les applis de la VM docker
en 503 ou en page de maintenance de Pangolin, le Newt des sites `docker`, `pi`,
`nas` et `proxmox-lxc` hors ligne. Les moniteurs Uptime Kuma (PikaPods) et
Telegram préviennent ; ntfy, Beszel, VictoriaLogs, Homepage et le site de
documentation étaient sur la VM docker et se taisent. **Lire cette page sur
GitHub** (`docs/runbooks/perte-totale-maison.md`) ou dans un clone.

## Diagnostic : ce qui reste, ce qui est perdu

**Reste, hors de la maison** (colonne « Survit à la maison » de la matrice) :

| Quoi | Où | Pour l'ouvrir |
|---|---|---|
| Dépôts Borg de tous les hôtes (applis, Immich, Pangolin, flip, Jellyfin) | Storage Box Hetzner, 9 instantanés quotidiens | `backup_passphrase` + une clé SSH d'un sous-compte (voir étage 1) |
| Pangolin et flip | VM Hetzner, intactes | clé SSH, ou console Hetzner |
| Secrets (SOPS) | dépôt privé `homelab-secrets` sur GitHub | compte GitHub + une clé age (`perso`, `pro` ou `secours`) |
| States Tofu | bucket OVH versionné | clés S3 et phrase de chiffrement, **dans les SOPS** |
| Bases KeePass | kDrive (Infomaniak) et restic horaire sur OVH (Object Lock 30 jours) | compte kDrive, ou compte OVH + mot de passe du dépôt restic |
| Code et runbooks | GitHub (public) | rien |
| kDrive (Infomaniak) | envois du téléphone, bases KeePass, et 1,27 To de films et séries hors du miroir du NAS (`Backups/Synology/tv`, `movies`, [kdrive-nas.md](kdrive-nas.md)) | compte Infomaniak |
| DNS, sites Pages, Uptime Kuma | OVH/Cloudflare, PikaPods | leurs comptes |

**Perdu sans recours** (rien de plus ancien à restaurer) :

- **Les médias du NAS** (`/volume1/media` : films, séries, musique, livres) :
  ni Borg ni miroir hors site, RAID 1 et instantanés Btrfs sur les mêmes
  disques. Seule issue : une copie que Sylvain aurait ailleurs, ou les
  ré-obtenir. Piste à vérifier : les films et séries de kDrive (ligne
  « kDrive » ci-dessus) sont-ils une copie de ces médias ? Le dépôt ne le dit pas.
- **Les archives vzdump** (images de la VM docker et du LXC) : seule copie sur
  le NAS ([ADR 0026](../adr/0026-vzdump-sur-le-nas-seul.md)). La VM se
  reconstruit **depuis Borg appli par appli**, pas depuis une image.
- **L'installation de l'hôte Proxmox** (système, réseau, disques). Sa
  configuration (`/etc/pve` : storages, realm OpenID, jetons, ACME) n'est pas
  perdue : elle est dans Borg (dépôt `pve_config`, depuis le 10/11/2026), à
  remettre à l'étage 3 ([hote-proxmox-mort.md](hote-proxmox-mort.md), partie
  **A bis**, jamais jouée).
- **Le miroir kDrive du NAS et son historique `versions/`** (anciennes versions
  de fichiers remplacés, absentes de kDrive) : le miroir se recopie depuis
  kDrive, pas `versions/`. Les films et séries exclus de la copie n'ont jamais
  été sur le NAS par ce rôle : ils restent chez kDrive.
- Les journaux VictoriaLogs,
  les réglages faits dans l'interface d'UGOS (dossiers partagés, comptes,
  droits) et l'installation de base du NAS et du Pi.
- **Les données écrites depuis la dernière nuit** : Borg tourne à 01:00 (NAS
  02:30), donc au plus une journée, deux si une nuit manquait. Les photos
  prises depuis ne sont que sur les téléphones : **ne rien supprimer sur les
  téléphones** avant la première sauvegarde de l'Immich reconstruit.
- **Sur le poste** : les couches 0 et 1 des KeePass (historique local), la clé
  age `perso` et la clé SSH `perso` si elles n'étaient que là.

## Réparation : les étages

On ne passe à l'étage suivant que si son **critère** est vrai. Les durées sont
celles de la matrice, sans le temps de se procurer du matériel.

### Étage 1. Secrets et accès

Rien d'autre ne démarre sans cet étage, et c'est lui qui porte les dépendances
circulaires (voir la feuille d'exercice) : chaque accès attend un second
facteur sur le **téléphone**.

1. Un poste de remplacement, connecté (la maison n'a plus de réseau : partage
   de connexion du téléphone, ou un autre lieu). Installer mise, puis dans un clone neuf
   (`git clone` du dépôt public) : `mise install`, `uv sync`.
2. Les **comptes** d'abord, avec le téléphone : GitHub, Hetzner (console),
   OVH, Infomaniak (kDrive). Où sont leurs identifiants et leurs seconds
   facteurs : à vérifier. Si les bases KeePass sont nécessaires pour les
   atteindre, les restaurer avant ([sauvegarde-keepass.md](sauvegarde-keepass.md),
   couches 2 et 3 : kDrive ou restic, mot de passe du dépôt restic).
3. Une **clé age** qui ouvre SOPS : `perso` et `pro` étaient peut-être sur le
   poste perdu ; `secours` est hors ligne, son lieu est « à vérifier » dans
   [perte-cle-ou-poste.md](perte-cle-ou-poste.md). Cloner le sous-module
   (`git submodule update --init`, compte GitHub et clé SSH autorisée sur
   `homelab-secrets`), puis `sops decrypt secrets/secrets.sops.yaml > /dev/null`.
4. Une **clé SSH** autorisée sur les hôtes : `keys/*.pub` (`perso`, `pro`,
   `android`). Sinon la console Hetzner (Pangolin, flip) et un nouveau
   `keys/perso.pub` ([perte-cle-ou-poste.md](perte-cle-ou-poste.md), « Clé SSH
   perso perdue ou volée »). Rejouer `00-setup.yaml` hôte par hôte est à la main.
5. L'accès à un dépôt Borg : `backup_passphrase` (SOPS) et la clé
   du sous-compte en lecture seule `restore-test` (`tofu output -raw
   storage_box_restore_test_ssh_private_key` dans `tofu/pangolin`, ce qui exige
   le state, donc les clés S3 des SOPS : [reconstruction-pangolin.md](reconstruction-pangolin.md),
   « Diagnostic »). Si le state est illisible, le compte principal de la Storage
   Box se gère dans la console Hetzner (créer un accès : à vérifier).
6. Le **compte principal de la Storage Box** accepte la clé SSH du poste
   neuf (console Hetzner, [perte-cle-ou-poste.md](perte-cle-ou-poste.md),
   « Clé SSH perso perdue ou volée », étape 5) : `backup.yaml` (étages 4 et 5) en dépend.
7. Poste ou clés **volés** (et non seulement détruits) : ne pas attendre
   l'étage 6. Retirer la clé SSH `perso` des hôtes et du compte GitHub, et
   commencer la rotation (jetons Hetzner et OVH d'abord) dès que l'étage 1
   passe ([perte-cle-ou-poste.md](perte-cle-ou-poste.md), « Clé age volée, ou poste volé »).
8. Hors de la maison, le jeton OVH de Tofu (`OVH_CONSUMER_KEY`), restreint à
   `home_ip`, refuse tout `plan` : en refaire un depuis le nouveau réseau par
   `ovh_credentials.py renew --allowed-ip <bloc>`, qui ne demande que la clé
   d'application ([rotation-des-secrets.md](rotation-des-secrets.md),
   « Consumer key de Tofu »).

**Critère de passage** : `sops decrypt` ouvre les deux fichiers SOPS ;
`borg list --bypass-lock <dépôt>` répond sur un dépôt d'appli
([intrusion-premiere-heure.md](intrusion-premiere-heure.md), étape 5, pour la
syntaxe) ; une session SSH ou console atteint Pangolin.

### Étage 2. Réseau et DNS

Où reconstruire, si la maison n'existe plus : le dépôt suppose un LAN
`192.168.1.0/24` à IP fixes (VM docker `.216`, LXC `.200`, hôte `.26`, NAS
`.137`, Pi `.96`, Bbox `.254`) et ne décrit **aucun** autre site. Deux voies :

- **Un nouveau lieu avec ce même plan d'adresses** : c'est la voie préparée.
  Box, DHCP, DNS annoncés, `home_ip`, Wi-Fi : [bbox-remplacee.md](bbox-remplacee.md).
  Garder la plage ; en changer touche `tofu/proxmox`, l'inventaire, Blocky,
  Pangolin et `known_hosts`.
- **Un hébergeur provisoire** (serveur Hetzner Cloud) : la VM docker a sa copie
  jetable, `tofu/pangolin/drill.tf` (éteinte par défaut), reconstruite depuis
  Borg par [reconstruction-vm-docker.md](reconstruction-vm-docker.md). Jouée une
  fois le 09/11/2026 (37 min, 15 dépôts Borg restaurés sur 17) ; la bascule en production (Newt, sauvegardes)
  n'y est pas rédigée. Le reste de la maison (NAS, Pi, Blocky) n'a pas
  d'équivalent.

En attendant, Pangolin et flip tiennent : Flip Planning reste en ligne.

Pour `home_ip` : le nouveau site a une nouvelle IP publique. Mettre `home_ip`
à jour dans les deux SOPS puis `tofu apply` dans `tofu/pangolin_config` et
`pangolin.yaml` (CrowdSec) ; **l'ancienne IP, réattribuée, garde l'accès sans
SSO** jusque-là.

**Critère de passage** : le LAN répond (`ping 192.168.1.254`), Internet sort,
`curl -sSI https://pangolin.sylvain.cloud` répond. Le DHCP annonce encore le
DNS de la box : `192.168.1.200` (Blocky du LXC) et `192.168.1.96` (Pi) ne
sont annoncés qu'une fois ces deux résolveurs revenus (étage 3 et Immich).

### Étage 3. Hôte Proxmox, ou machine de remplacement

Une machine x86 capable de la VM docker (3 cœurs, 12 Gio, disque de 190 Gio
virtuels dont ~105 Gio écrits, `tofu/proxmox/terraform.tfvars`). Pas d'archive
vzdump : [hote-proxmox-mort.md](hote-proxmox-mort.md), parties **A** (installer
l'hôte, jeton d'API, clé d'hôte en PR), **A bis** (remettre `/etc/pve` depuis
Borg, avant de recréer quoi que ce soit) et **C** (« NAS aussi perdu » : recréer
par Tofu).

1. `mise run init-proxmox`, `mise run plan-proxmox`, relire, puis
   `mise run apply-proxmox` (Sylvain applique).
   Le NAS n'existe plus : `proxmox_storage_nfs.nas_backup` et
   `proxmox_backup_job.nightly` (`backup.tf`) ne peuvent pas être créés. Lire
   le plan et n'appliquer que la VM et le LXC (`apply -target` : lire d'abord
   `plan -target`, un apply ciblé applique aussi les dépendances) ; stockage et
   job reviennent avec le NAS (étage 6).
2. Le LXC newt : Tofu le crée, `lxc.yml` le configure (à la main, jamais en
   CI). Il rend le site `proxmox-lxc` (accès à la maison depuis Internet et
   chemin de la CI) et le deuxième Blocky ; une fois Blocky répondant, faire annoncer
   `192.168.1.200` par le DHCP.
3. **`ansible/known_hosts` est strict** : la clé de chaque hôte neuf se lit
   sur l'hôte (console), jamais par `ssh-keyscan`, et se committe par PR
   ([cle-hote-ssh-changee.md](cle-hote-ssh-changee.md)).

**Critère de passage** : `qm list` et `pct list` montrent la VM 100 et le LXC
200 en cours ; le site `proxmox-lxc` est en ligne dans Pangolin ; `dig +short
@192.168.1.200 example.com` répond.

### Étage 4. VM docker

Sans machine Proxmox, la VM se reconstruit sur un serveur Hetzner Cloud jetable :
[reconstruction-vm-docker.md](reconstruction-vm-docker.md) (procédure, feuille de
temps, vérification par appli). Ce qui suit vaut pour une VM sur Proxmox.

1. Depuis `ansible/`, avec `--check --diff` d'abord : `ansible-playbook
   00-setup.yaml --limit docker`, puis `docker.yml --tags setup` (Docker,
   security, borgmatic, newt).
2. `ansible-playbook backup.yaml` : autorise la clé de root de la VM neuve chez
   son sous-compte (même mécanique que
   [sauvegarde-et-restauration.md](sauvegarde-et-restauration.md), « Clé non
   autorisée »). Le playbook lit la clé de `docker`, `pi`, `pangolin`, `flip`,
   `nas` et `pve` et refuse tout si l'une manque : Pi et NAS absents, le limiter aux
   hôtes présents avec `-e '{"backup_storage_box_hosts": ["docker"]}'` (à vérifier
   en `--check`), et refaire de même pour le Pi à l'étage 5.
3. `ansible-playbook docker.yml` pour le reste de la pile. Les applis démarrent
   **à vide** : les arrêter avant de leur rendre leurs données, et ne pas laisser
   la sauvegarde de 01:00 d'une appli encore vide passer avant sa restauration
   (arrêter son minuteur borgmatic).

**Pas de merge qui déploie pendant la reprise.** Un merge sur `main` qui touche
`ansible/roles/**`, un playbook ou `docs/**` lance `deploy-docker-app` : tant
que le LXC et les sites ne sont pas revenus, il échoue, et une fois revenus il
déploie sur des hôtes à moitié restaurés
([deploiement-ci-casse.md](deploiement-ci-casse.md)). Travailler sur des
branches, déployer depuis le poste (`ansible-playbook`), merger après l'étage 6.

**Critère de passage** : sur la VM, `systemctl --user list-units 'dc@*'
--state=failed` est vide ; le site `docker` est en ligne dans Pangolin ;
`borgmatic --config /etc/borgmatic.d/<app>.yaml list` répond pour une appli.

### Étage 5. Les applis du foyer (étage 1 de la matrice)

La matrice classe en étage 1 : Immich, Nextcloud, Dawarich, HealthLog, Papra. Pour chacune, la restauration
appli par appli de [sauvegarde-et-restauration.md](sauvegarde-et-restauration.md),
en **arrêtant l'appli avant** de rejouer son dump. Proposition d'ordre :

1. **Immich d'abord, en tâche de fond** : l'extraction de `library` est la
   plus longue (taille et durée jamais relevées). Immich ne dépend ni de
   Proxmox ni de la VM docker, seulement des étages 1 et 2 : il peut démarrer
   dès l'étage 2 passé, en parallèle des étages 3 et 4. Le Pi n'existe plus ;
   [pi-mort.md](pi-mort.md) suppose un Pi réinstallé. Sur un autre support
   qu'un Pi (x86, la VM docker), `pi.yml` ne s'applique pas tel quel : c'est
   à écrire le jour venu (à vérifier, [ADR 0020](../adr/0020-garder-le-raspberry-pi-pour-immich.md)).
   Un Pi neuf a une **nouvelle adresse MAC** : réservation de la box à refaire.
2. **Nextcloud** (calendriers, fichiers : `compose`, `config`, `data`, `redis`
   et dump MariaDB), puis **HealthLog** (sa clé de chiffrement dérive de
   `backup_passphrase` : la même phrase de passe, sinon les colonnes
   chiffrées ne s'ouvrent pas), **Dawarich**, **Papra**.
3. Le **site de documentation** (`docs_site`) et ntfy reviennent avec la pile :
   les alertes ntfy recommencent à ce moment, pas avant.
4. **Second passage Ansible, une fois les données restaurées** :
   `ansible-playbook docker.yml --tags backup` (idem `pi.yml --tags backup`
   pour le Pi et `nas.yml --tags backup` pour le NAS, à la main). Ansible ne
   repère une base SQLite (copie cohérente avant sauvegarde, exclusion du
   fichier vivant) que si le fichier existe : au premier passage les bases
   n'étaient pas là, et sans ce passage les bases vivantes partent à chaud
   chaque nuit. Vérifier ensuite que l'archive suivante contient
   `var/lib/borgmatic-sqlite`.

**Critère de passage**, par appli : l'adresse répond derrière le SSO, les
données attendues sont là (une photo récente, un calendrier, une mesure), le
moniteur Uptime Kuma est vert, et la sauvegarde de 01:00 suivante réussit
(moniteur « Backup <appli> »). Le foyer retrouve ses photos et ses
calendriers : le dire.

### Étage 6. Le reste

Par ordre de valeur, sans urgence :

- Les applis d'étage 2 et 3 de la matrice (Monica, Karakeep, Homebox, Grocy,
  TREK, BookStack, Wishlist, FreshRSS, Beszel, ntfy…), depuis Borg.
- **Le NAS**, si un nouveau est acheté : [disque-nas-mort.md](disque-nas-mort.md),
  partie **B** (UGOS, dossiers partagés, `nas.yml`, Jellyfin depuis Borg,
  job vzdump, première copie de kDrive à la main). Les médias repartent de
  la copie que Sylvain aura, sinon de rien.
- Le job vzdump (`tofu/proxmox/backup.tf`) à recréer avec le NAS, puis une
  archive à la main sans attendre 21:00.
- **Le reste de la sécurité** : rotation des secrets du poste perdu (faite
  dès l'étage 1 si le poste a pu être volé), si rien ne prouve qu'il n'est pas dans de mauvaises mains (voir
  [perte-cle-ou-poste.md](perte-cle-ou-poste.md), « Poste perdu »), puis
  seulement les merges qui déploient.
- Mettre à jour [matrice-des-donnees.md](../matrice-des-donnees.md) et les
  runbooks de ce qui a surpris.

## Vérification

- Tous les moniteurs Uptime Kuma verts, ntfy reçoit un message, Beszel voit
  les hôtes.
- Une nuit de sauvegarde complète passe : chaque moniteur « Backup … » vert le
  lendemain, 26 h au plus.
- Le test de restauration de la CI (1er et 15 du mois) passe, ou se lance à la
  main (`restore-test.yaml`).
- `tofu plan` dans chaque module concerné ne montre aucune dérive inattendue ;
  un merge de test qui déploie passe.
- Le foyer confirme que ses photos, calendriers et documents sont là.

## Prévention

Ce que le scénario montre et que le dépôt ne règle pas (les trous 1, 3, 5, 6, 9
de la matrice) :

- **Écrire hors du dépôt public** où sont rangés : la clé age `secours` et `pro`,
  le mot de passe du dépôt restic des KeePass, `backup_passphrase`, les seconds
  facteurs des comptes. S'ils sont dans la maison, ils partent avec elle.
- Garder un **autre moyen de second facteur** (codes de secours imprimés ou un
  deuxième appareil enrôlé) pour GitHub, Hetzner, OVH et Infomaniak.
- Rejouer la feuille ci-dessous une fois, puis chaque année.
- Mesurer, une fois, la durée d'extraction d'Immich et de restauration de la
  VM : la matrice n'a que des estimations.
- Décider du sort des médias (copie hors site, ou assumer la perte).

---

## Feuille d'exercice : reprise depuis un PC vierge

À jouer par Sylvain, en **lecture seule** : on prouve qu'on atteint chaque
élément, on ne change rien sur les hôtes et on ne restaure rien. Le but est de
faire apparaître les **boucles** : une chose dont on a besoin pour obtenir la
chose dont on a besoin pour l'obtenir.

**Mise en place.** Un PC sans rien de Sylvain : session neuve, ou clé USB
live, ou autre ordinateur. Le **téléphone** est le seul objet de la maison
autorisé, parce qu'il sera peut-être le seul survivant (il peut aussi être perdu :
refaire l'exercice une fois sans lui, avec les seuls codes de secours). Pas de gestionnaire de mots de passe déjà ouvert, pas de
navigateur connecté, pas de `~/.config/sops`, pas de `~/.ssh`. Chronomètre. Un
papier (ou un fichier **hors du dépôt**) pour noter, à chaque ligne : le temps,
ce qui a bloqué, ce qu'il a fallu improviser.

**Règles.** Aucune session déjà ouverte n'est permise. Le lieu de
rangement d'un secret se note sur le papier, jamais dans le dépôt. Si une
ligne est impossible sans une chose qu'on n'a pas, on l'écrit : c'est une
boucle trouvée, et on passe à la suivante en admettant ce qu'on a.

| # | Je dois… | Il me faut | Ce que l'exercice révèle |
|---|---|---|---|
| 1 | **Déverrouiller le téléphone** et ouvrir l'application de second facteur | le téléphone, son code | tout le reste en dépend. Où sont les codes de secours si le téléphone est perdu ? |
| 2 | Me connecter au courrier ou au compte qui reçoit les réinitialisations | téléphone (étape 1) | un mot de passe oublié passe par le courrier, qui veut son second facteur |
| 3 | Me connecter à GitHub | mot de passe, second facteur du téléphone | sans lui : ni clone du sous-module secrets, ni CI. Où est le mot de passe sans KeePass ? |
| 4 | Cloner le dépôt public, puis `mise install`, `uv sync` | réseau, GitHub (public : aucun compte) | l'installation de mise et d'`uv` passe par Internet : vérifier |
| 5 | `git submodule update --init` (dépôt privé `homelab-secrets`) | une clé SSH ou un jeton GitHub | la clé SSH est dans KeePass ; KeePass est sur kDrive ou OVH : **boucle A** |
| 6 | Ouvrir KeePass : se connecter à kDrive (Infomaniak), télécharger la base | compte Infomaniak, second facteur (étape 1), puis le mot de passe de la base | le mot de passe de la base est-il dans la base ? |
| 7 | Sinon, restaurer la base depuis restic (OVH) | compte OVH, **mot de passe du dépôt restic** (hors du poste et hors de la maison ?) : **boucle B** si on ne l'a que derrière une clé age | ce mot de passe est-il atteignable sans ce qu'on cherche à restaurer ? |
| 8 | Obtenir une clé age (`secours`) | son support hors ligne ([test-cle-secours.md](test-cle-secours.md)) | où est-il ? Si dans la maison : fin de partie, sauf `perso` ou `pro` ailleurs |
| 9 | `sops decrypt secrets/secrets.sops.yaml > /dev/null`, idem `ansible.sops.yaml` | 5 et 8 | la preuve que les secrets sont atteignables |
| 10 | Lire le state Tofu (`mise exec -- tofu -chdir=tofu/pangolin output`, en lecture seule) | clés S3 et phrase de chiffrement **dans les SOPS** (9) | le state est la porte de l'inventaire et de la clé `restore-test` |
| 11 | Ouvrir la console Hetzner et se connecter en SSH à Pangolin (sans rien modifier) | compte (3 ou 6), clé SSH (5) | clé SSH sur le poste perdu : boucle A |
| 12 | Lister un dépôt Borg : `borg list --bypass-lock <dépôt>` (étape 5 de [intrusion-premiere-heure.md](intrusion-premiere-heure.md)) | `backup_passphrase` (9, ou une copie hors SOPS), clé `restore-test` (10) | la phrase de passe est-elle ailleurs que dans SOPS ? |
| 13 | Lire cette page et les runbooks sans le site de docs (SSO de Pangolin) | GitHub | la doc privée n'est pas lisible si Pangolin tombe : GitHub suffit |
| 14 | Joindre le foyer (téléphone, messagerie) et lui dire ce qui se passe | le téléphone | personne d'autre que Sylvain n'a la procédure |

**À la fin.** Pour chaque boucle trouvée, une action : un papier imprimé hors
de la maison, un code de secours, une copie d'un secret chez une personne de
confiance ou dans un coffre, un deuxième appareil enrôlé. Noter la date de
l'exercice ici (PR) pour savoir quand le refaire, et corriger la matrice si un
« à vérifier » est tranché.
