# Matrice des données

Une ligne par appli ou jeu de données (l'hôte est le titre de chaque tableau) :
où il vit, combien de copies, ce qui survit si la maison disparaît, ce qu'on
peut perdre au maximum, le temps de reprise estimé, et ce qui n'est pas protégé. Base du runbook de perte
totale de la maison ([perte-totale-maison.md](runbooks/perte-totale-maison.md)).
Ce n'est pas une procédure : pour restaurer, voir
[sauvegarde-et-restauration.md](runbooks/sauvegarde-et-restauration.md) et
[backup-restore.md](backup-restore.md).

Rien ici n'a été lu sur les hôtes : tout vient du dépôt (état au 05/11/2026,
revu le 10/11/2026).
Ce que le dépôt ne dit pas est écrit « non trouvé dans le dépôt, à vérifier
sur l'hôte », ce qui ne veut pas dire que c'est absent.

Sinistres visés : **panne matérielle**, **maison sinistrée** (NAS, hôte
Proxmox, Pi et poste perdus ensemble), **compromission**. Dépendants : Sylvain,
le foyer, la famille. Le dépôt ne dit pas qui utilise quelle appli, sauf
Immich (« le service le plus utilisé de la famille »,
[ADR 0020](adr/0020-garder-le-raspberry-pi-pour-immich.md)), Wishlist (listes
partagées avec la famille) et Jellyfin (un compte par personne du foyer,
[media.md](media.md)). Le reste du classement est une proposition, à corriger
par Sylvain.

## Lire les tableaux

**Étages** (critère écrit, proposition de classement) :

| Étage | Critère |
|---|---|
| 1 | Pas d'autre source connue dans le dépôt, perte définitive et difficile à refaire (souvenirs, documents), touche une personne du foyer ; ou secret dont la perte bloque toute la reprise. |
| 2 | Donnée saisie à la main ou historique : se refait en jours, même si sa perte serait définitive (listes, comptes, réglages), ou existe en partie ailleurs ; ou accès à reconstruire. |
| 3 | Se reconstruit depuis le dépôt (Tofu, Ansible) ou jetable (mesures, journaux, caches). |

**Copies** : « Borg » = dépôt `backup/<hôte>/<appli>` sur la Storage Box
Hetzner (`fsn1`), chiffré, 7 quotidiennes, 4 hebdomadaires,
6 mensuelles, 1 annuelle, plus 9 instantanés quotidiens de la box
([architecture.md](architecture.md#les-sauvegardes)). « vzdump » = image de
l'hôte Proxmox sur le NAS (voir la ligne de la VM).

**Perte maximale** : déduite de la fréquence. Borg tourne à 01:00 (NAS 02:30) :
**au plus une journée** de données, deux si une nuit manque (l'alerte part
après 26 h, le test de restauration refuse une archive de plus de 28 h). Le
chiffre n'est donné que quand il diffère.

**Reprise** : toujours une **estimation**, sauf mention « mesuré ». Elle compte
le temps de restauration des données une fois l'hôte réinstallé et accessible,
pas le temps de se procurer du matériel.

**Test** : « CI » = `restore-test.yaml`, le 1er et le 15 du mois, depuis un
runner GitHub : dernière archive de moins de 28 h, dumps rejoués dans un
conteneur jetable, copies SQLite vérifiées (`integrity_check`), tables
attendues non vides, échantillon de 20 fichiers de 5 Mio au plus
([restore-test/README.md](../.github/restore-test/README.md)). Il ne démarre pas
l'appli et ne compare rien au vivant. Pas de vérification de tous les blocs
([ADR 0017](adr/0017-pas-de-verification-complete-des-donnees.md)).

## Machine par machine

### Hôte Proxmox (`pve`) et VM docker

La VM docker (id 100, 3 cœurs, 12 Gio) tourne sur le SSD M.2 SATA de l'hôte,
dans la maison. Toutes les applis de ce tableau y sont, sauf mention.

| Donnée | Étage | Copies | Survit à la maison | Reprise (est.) | Test | Non protégé |
|---|---|---|---|---|---|---|
| **VM docker entière** (disque ~190 Gio virtuels, ~105 Gio écrits) | 3 | vzdump nocturne 21:00 sur le NAS, 2 dernières archives, seule copie ([ADR 0026](adr/0026-vzdump-sur-le-nas-seul.md)) | non (même maison que le NAS) | VM elle-même jamais restaurée ; reconstruite depuis Borg sur un serveur jetable le 09/11/2026 en **37 min** ([exercice](runbooks/reconstruction-vm-docker.md) : 15 dépôts Borg sur 17, FreshRSS non restaurée alors (rôle corrigé depuis, à confirmer au prochain exercice), Open WebUI sans archive alors) | archive lue en entier (`vma verify`) le 2 et le 16, **pas restaurée** : l'hôte n'a pas la mémoire | archives non chiffrées (secrets des applis dedans) ; perte max 1 jour |
| **LXC newt** (id 200 : Newt du site `proxmox-lxc`, Blocky) | 3 | vzdump (NAS) ; recréable par `tofu/proxmox` + `lxc.yml` | non | < 1 h (est.) | restauré sur un id jetable, démarré sans réseau, le 2 et le 16 | `lxc.yml` ne tourne jamais en CI |
| **Configuration de l'hôte Proxmox** (`/etc/pve` = base `config.db` de pmxcfs : storages, utilisateurs, realm OpenID, jetons, pare-feu, SDN, jobs, ACME ; plus `/etc/network/interfaces`, `hosts`, `hostname`, `resolv.conf`) | 2 | Borg `pve_config` à 01:00 (sous-compte `pve`, copie `VACUUM INTO` de la base, rôle `pve_config_backup`). Reproduisibles par le dépôt : invités (`tofu/proxmox`), pare-feu et SSH (`pve_hardening`), `vzdump.conf` (`pve.yml`) | oui (Borg) | < 1 h après l'installation (est.), [hote-proxmox-mort.md](runbooks/hote-proxmox-mort.md) « A bis » : **jamais jouée** | CI (copie SQLite, table `tree`) | installation de l'hôte « à la main » ; `fstab`, LVM, clés d'hôte SSH exprès hors archive |
| Nextcloud | 1 (par prudence : calendriers Perso et Top nous nommés dans le dépôt, contenu des fichiers non précisé) | Borg : `compose`, `config`, `data`, `redis` + dump MariaDB | oui | quelques heures (est.), plus long si `data` est gros (taille non relevée) | CI | rien hors du dernier jour |
| Dawarich (historique de position) | 1 | Borg : `storage`, `public`, `watched`, `redis` + dump PostgreSQL | oui | ~1 h (est.) | CI | clés dérivées de `backup_passphrase` (voir « Secrets ») |
| HealthLog (poids, tension, sommeil, analyses) | 1 | Borg : dump PostgreSQL + `compose.yaml` + `.env` | oui | ~1 h (est.) | CI ; la clé de chiffrement de l'appli n'y est pas éprouvée | dump interne de l'appli coupé ; `healthlog_backups` hors Borg ; `ENCRYPTION_KEY` dérivée de `backup_passphrase` |
| Papra (documents scannés) | 1 | Borg : `app-data` (SQLite + originaux), `.env` | oui | ~10 min pour 795 Mo (mesuré le 02/11 : extraction 21 s) | CI | a remplacé Paperless-ngx (retiré le 07/11/2026, dépôt Borg détruit) |
| Monica | 2 | Borg : `data` + dump MariaDB | oui | ~30 min (est.) | CI | — |
| Karakeep (marque-pages) | 2 | Borg : `data` + copies SQLite | oui | ~30 min (est.) | CI | `queue.db` (file de jobs) copiée aussi, vide par nature ; jobs en cours perdus avec le dernier jour |
| Homebox (inventaire, factures, garanties) | 2 | Borg : `data` + copie SQLite | oui | ~30 min (est.) | CI | — |
| Jellystat (historique de lecture de Jellyfin) | 2 | Borg : dump PostgreSQL + `compose.yaml` + `.env` | oui | ~30 min (est.) | CI | `backup-data/` (sauvegardes JSON à la demande) hors Borg |
| Yamtrack (suivi de médias) | 2 | Borg : copie SQLite (`.backup`) + `compose.yaml` + `.env` | oui | ~30 min (est.) | CI | Redis (cache et file) hors Borg |
| Open WebUI (chat, conversations) | 2 | Borg : `data` (uploads) + copie SQLite (`VACUUM INTO`) + `compose.yaml` + `.env` | oui | ~30 min (est.) | CI | `data/cache` exclu (se retélécharge) ; aucune donnée ailleurs, les modèles sont chez Anthropic par la passerelle |
| Grocy | 2 | Borg : `config` + copie SQLite | oui | ~30 min (est.) | CI | `log` et `viewcache` exclus (jetables) |
| TREK (voyages) | 2 | Borg : `data`, `uploads` + copie SQLite | oui | ~30 min (est.) | CI | — |
| BookStack (wiki) | 2 | Borg : `config` + dump MariaDB | oui | ~30 min (est.) | CI | — |
| Wishlist (listes de cadeaux de la famille) | 2 | Borg : `data`, `uploads` + copie SQLite | oui | ~30 min (est.) | CI | — |
| FreshRSS | 2 | Borg : `freshrss_data`, `extensions` + copies SQLite par utilisateur | oui | ~30 min (est.) | CI | cache exclu |
| Bétisier | 3 | Borg : `config`, `dump.sql` + dump MariaDB | oui | ~30 min (est.) | CI | — |
| Beszel (hub de supervision) | 3 | Borg : `beszel_data` + copies SQLite | oui | ~30 min (est.) | CI | — |
| ntfy | 3 | Borg : `config`, `user.db` | oui | ~30 min (est.) | CI | comptes et jetons sont déclarés par le rôle |
| Speedtest Tracker | 3 | Borg : `config` + copie SQLite | oui | ~30 min (est.) | CI | — |
| Homepage, Enclosed, MkDocs (`docs_site`), Neonova | 3 | aucune ; sans état ou jetable, redéployés par Ansible | sans objet | < 30 min chacune (est.) | non | notes d'Enclosed éphémères exprès |
| VictoriaLogs (journaux, 30 jours) | 3 | aucune, « reproductibles » | non | sans objet | non | tous les journaux |
| MediaManager (essai, NAS) | 3 | config en Borg (NAS) et dump PostgreSQL (`pg_dump -Fc` par l'hôte juste avant, 02:30) | oui | ~30 min (est.) | exclu du test (raison écrite dans `check_restore_coverage.py`) | rien hors du dernier jour |

### Raspberry Pi (`pi`)

| Donnée | Étage | Copies | Survit à la maison | Reprise (est.) | Test | Non protégé |
|---|---|---|---|---|---|---|
| **Immich : originaux** (`library`) | 1 | Borg `immich` à 01:00 : `library` entier (originaux, vignettes, vidéos transcodées), `timelapse_output`, `timelapse_config`. **Seule copie** en plus du disque USB du Pi (pas de vzdump) | oui (Borg) | non mesuré : dépend du volume, taille non relevée ; extraction depuis la Storage Box, une journée ou plus (est.) | CI : liste de l'archive, dump de la base et échantillon seulement ; originaux non extraits en entier | un fichier envoyé depuis la dernière nuit ; blocs corrompus hors échantillon (ADR 0017) |
| Immich : base PostgreSQL | 1 | même dépôt, dump fait dans le conteneur `immich_postgres` | oui | ~1 h (est.) | CI : dump rejoué, table non vide | — |
| Immich Swipe, Selfie Timelapse | 3 | Swipe sans état ; sorties du timelapse dans le dépôt Borg ci-dessus | oui | < 30 min (est.) | non | clés d'API dans SOPS |
| Blocky (DNS) | 3 | aucune, config par Ansible ; une 2e instance sur le LXC | oui (via le dépôt) | < 30 min (est.) | non | — |
| Système du Pi | 3 | aucune ; `pi.yml` reconfigure | sans objet | non trouvé dans le dépôt (installation « à la main ») | non | image de l'OS, installation de base |

### NAS Ugreen (UGOS, RAID 1)

Disques surveillés par l'agent Beszel : `sda`, `sdb` (SATA), `sdc` (USB), voir `host_vars/nas` ;
par `smart_check` (alerte hebdomadaire) : `sda` et `sdb`, `sdc` retiré depuis son décrochage du 05/11 (`nas.yml`).

| Donnée | Étage | Copies | Survit à la maison | Reprise (est.) | Test | Non protégé |
|---|---|---|---|---|---|---|
| **Médias** (`media` : films, séries, musique, livres) | 2 | RAID 1 et instantanés Btrfs d'UGOS ; **pas dans Borg** | non | sans objet : à ré-obtenir ; origine non précisée dans le dépôt | non | panne des deux disques, vol, incendie, suppression au-delà des instantanés (fréquence non trouvée dans le dépôt) |
| Jellyfin : config et base | 2 | Borg `jellyfin` à 02:30 (conteneur borgmatic), copies SQLite | oui | ~30 min (est.) | CI | médias (ligne précédente) |
| **Miroir de kDrive** (`kdrive` : `miroir/` + `versions/`) | 2 | `rclone copy` à 04:00, jamais de suppression ; **pas dans Borg** (décision du 07/11 : ne tient pas sur la Storage Box ; `kdrive_sync_backup_enabled: false`) ; instantanés Btrfs d'UGOS sur `kdrive`, réglés à la main : un par jour à 00:00, gardés 14 jours (relevé du 07/11, [kdrive-nas.md](runbooks/kdrive-nas.md)) | non (l'original est chez Infomaniak) | re-copie depuis kDrive : non mesuré, ~0,95 To (relevé du 16/10) | non | films et `Videos/` exclus de la copie ; miroir et NAS dans la même maison (perte simultanée avec kDrive = rien) ; un fichier modifié à taille égale n'est pas recopié |
| **Archives vzdump** (`pve-backup`) | 3 | voir la VM docker | non | — | voir la VM docker | non chiffrées, sans partage SMB, export réservé à l'IP de l'hôte |
| Config de MediaManager, qBittorrent, Prowlarr | 3 | Borg (avec le dump de la base) | oui | ~30 min (est.) | exclu | voir plus haut |
| Système UGOS (dossiers partagés, comptes, droits) | 2 | `nas.yml` pose les exports NFS ; dossiers partagés créés dans l'interface | sans objet | non trouvé dans le dépôt, à vérifier sur l'hôte | non | réglages faits dans l'interface UGOS |

### Pangolin (Hetzner, nbg1)

| Donnée | Étage | Copies | Survit à la maison | Reprise | Test | Non protégé |
|---|---|---|---|---|---|---|
| Pangolin : base SQLite, `config/` (certificats, clés), `compose.yaml` | 2 (porte l'accès public et les identifiants des sites : les Newt se reconnectent seuls si la base revient, [reconstruction-pangolin.md](runbooks/reconstruction-pangolin.md)) | Borg `pangolin` à 01:00 (~10 Go, dont ~7,7 Go de copies de migration) ; en plus 7 images quotidiennes Hetzner de la VM (restent chez Hetzner) | oui | ~45 min de bout en bout (**mesuré** le 28/10 sur une VM jetable) | CI | journaux Traefik exclus ; perte max 1 jour |
| Pocket ID ([ADR 0030](adr/0030-pocket-id-fournisseur-identite-pilote.md)) : base SQLite (comptes, passkeys, clients OIDC), `data/`, `.env` (clé de chiffrement) | 3 (les passkeys se refont par un code créé sur l'hôte, [pocket-id.md](runbooks/pocket-id.md)) | Borg `pocket_id` de la VM Pangolin | oui | ~15 min (est.) | CI | rien |

### flip (Hetzner, fsn1, sans IP publique)

| Donnée | Étage | Copies | Survit à la maison | Reprise (est.) | Test | Non protégé |
|---|---|---|---|---|---|---|
| Flip Planning, production | 2 | Borg `flip_planning` : `compose.yaml`, `pgadmin` + dump PostgreSQL ; pas d'image Hetzner (`backups = false`) | oui | ~1 h (est.), plus la reconstruction de la VM | CI | — |
| Flip Planning, démo | 3 | Borg `demo_planning` (sa propre archive) | oui | ~1 h (est.) | CI | — |
| Démo Keycloak (**en pause**), vitrine publique (**en pause**) | 3 | aucune (`flip_planning_backup_enabled: false`) | non | sans objet | non | toutes leurs données, gardées sur le disque de flip |
| Promptoramix | 3 | aucune ; son volume est un journal de coups, hors sauvegarde | non | sans objet | non | ce journal |

## Hors de la maison, mentionné dans le dépôt

| Donnée | Étage | Où | Copies | Survit à la maison | Test | Non protégé |
|---|---|---|---|---|---|---|
| **Dépôts Borg** de tous les hôtes | 1 | Storage Box Hetzner `bx11`, `fsn1`, un sous-compte par hôte | 9 instantanés quotidiens de la même box ; `delete_protection` ; **aucune autre copie** | oui, c'est la copie hors site | CI (tous les dépôts de `apps.json`) | Hetzner est le seul hébergeur ; usage contrôlé le lundi (alerte à 80 %) |
| **kDrive** (envois du téléphone, bases KeePass synchronisées) | 1 | Infomaniak ; le NAS en garde un miroir | miroir NAS (voir plus haut) | oui, chez Infomaniak | — | — |
| **Bases KeePass** | 1 | poste : `kdrive/keepass/*.kdbx` | copie avant enregistrement, historique horodaté sur le poste ; restic **horaire** vers un bucket OVH (Object Lock 30 jours) | oui : OVH et kDrive | `restic check` + restauration comparée, mensuel ; test à froid trimestriel ([sauvegarde-keepass.md](runbooks/sauvegarde-keepass.md)) | les deux premières couches sont sur le poste ; perte max 1 h |
| **States Tofu** | 1 | bucket OVH `homelab-tf-state-sylvain`, versionné ([opentofu.md](conventions/opentofu.md)) | versions du bucket | oui | non | `pangolin_config` et `dns` en clair (lus par Ansible) ; passphrase de chiffrement dans SOPS |
| **Secrets** (`secrets.sops.yaml`, `ansible.sops.yaml`, inventaire de rotation) | 1 | dépôt privé `homelab-secrets` sur GitHub, sous-module ([ADR 0018](adr/0018-secrets-depot-prive.md)) | clones sur les postes ; chiffré pour 3 clés age (`perso`, `pro`, `secours`) + CI | oui, côté GitHub | à chaque PR : destinataires vérifiés au Lint ; clé `secours` ouverte chaque trimestre ([test-cle-secours.md](runbooks/test-cle-secours.md)) | emplacement des clés `pro` et `secours` : « à vérifier » dans [perte-cle-ou-poste.md](runbooks/perte-cle-ou-poste.md) |
| `backup_passphrase` (une seule pour tous les dépôts Borg) | 1 | SOPS ; le runbook demande de la garder aussi dans un gestionnaire de mots de passe | — | à vérifier | — | sans elle, aucun dépôt ne s'ouvre ; dérive aussi les clés de HealthLog et Dawarich |
| Mot de passe du dépôt restic des KeePass | 1 | papier + SOPS des dotfiles | — | lieu du papier non trouvé dans le dépôt | trimestriel (test à froid) | — |
| Code, runbooks, Tofu, Ansible | 1 | dépôt GitHub public ; docs aussi sur `docs.sylvain.cloud` | clones locaux | oui | CI | le site de docs passe par le SSO de Pangolin : GitHub sert quand Pangolin tombe |
| DNS (`tofu/dns`), sites Pages (Cloudflare) | 3 | enregistrements dans le dépôt ; sites dans leurs dépôts | — | oui | non | — |
| Uptime Kuma (PikaPods) | 3 | moniteurs déclarés dans `tofu/pangolin_config` | recréables | oui | non | historique des mesures : non trouvé dans le dépôt |

## Par sinistre

| Sinistre | Perdu | Reste |
|---|---|---|
| Panne de la VM docker ou de l'hôte Proxmox | l'état entre 01:00 et la panne | Borg de chaque appli et de la config de l'hôte (`pve_config`) ; image vzdump si le NAS tient |
| Panne du Pi | Immich en ligne tant que le Pi est absent | Borg `immich` ; le disque USB peut survivre |
| Panne du NAS | médias si les deux disques tombent ; images vzdump ; miroir kDrive | Borg (config de Jellyfin, de MediaManager avec le dump de sa base) ; kDrive chez Infomaniak ; aucune appli de la VM docker ne garde ses données sur le NAS aujourd'hui (`nas_storage`) |
| Panne de Pangolin ou flip | accès public ; flip n'a pas d'image Hetzner | Borg ; images Hetzner de Pangolin ; ~45 min pour Pangolin (mesuré) |
| **Maison sinistrée** | VM docker, Pi, NAS (médias, miroir kDrive, images vzdump), poste (couches KeePass 0 et 1, clé age `perso` si seule) | tous les dépôts Borg (dont Immich), Pangolin et flip, kDrive, KeePass (OVH), states, secrets (GitHub), dépôt de code |
| **Compromission** d'un hôte | ce que root de cet hôte efface de ses dépôts | les 9 instantanés (aucun sous-compte ne peut les effacer) ; les dépôts des autres hôtes. Un jeton Hetzner en écriture volé peut lever la protection de la box ([storage_box.tf](../tofu/pangolin/storage_box.tf)) |
| Compromission du poste ou d'une clé age | rien d'immédiat | l'historique git garde les anciens secrets : il faut les changer ([perte-cle-ou-poste.md](runbooks/perte-cle-ou-poste.md)) |

## Les deux points tranchés

1. **Originaux d'Immich : oui, dans Borg.** Le rôle `immich` met en sources
   `<immich_base_path>/library` (`UPLOAD_LOCATION=./library` dans
   `templates/env.j2`), `timelapse_output`, `timelapse_config`, `compose.yaml`,
   `.env`, et ajoute le dump PostgreSQL (`ansible/roles/immich/tasks/main.yml`).
   Seules exclusions : `*.log` et `*.tmp` (défauts de `borgmatic`). Ce que le
   test de restauration en prouve est mince : la liste de l'archive, le dump
   et un échantillon ([restore-test/README.md](../.github/restore-test/README.md)).
2. **`/etc/pve` : sauvegardé depuis le 10/11/2026** (relevé sur l'hôte : rien
   ne le sauvegardait avant). Borg `pve_config`, rôle `pve_config_backup` ;
   restauration écrite, jamais jouée. **Scrub Btrfs du NAS : aucun planifié
   par le dépôt, par choix** (UGOS n'est pas géré par Ansible : [sante-des-disques.md](runbooks/sante-des-disques.md),
   « Scrub Btrfs du NAS ») ; au relevé du 05/11, aucun scrub n'avait tourné
   (`btrfs scrub status` : « no stats available »). Un scrub planifié dans
   UGOS : à vérifier sur l'hôte. Le S.M.A.R.T. des disques est lu par Beszel
   (verdict global) et, chaque lundi, par `smart_check` (secteurs et usure,
   alerte sur une hausse, #1207).

## Limites décidées (faits, pas des manques)

- vzdump sur le NAS seul, sans copie hors site ([ADR 0026](adr/0026-vzdump-sur-le-nas-seul.md)) :
  le NAS perdu, plus d'image de la VM ni du LXC.
- Écartés le 05/11/2026 par Sylvain : copie froide hors Hetzner, Borg en
  ajout seul (append-only), miroir GitHub, archive du courrier.
- La perte d'un compte fournisseur (Hetzner, OVH, Infomaniak, GitHub) n'est
  pas un scénario visé.

## Les trous

Ce que la matrice montre et qui n'est ni décidé ni couvert. Aucun achat
proposé ici.

1. **Médias du NAS** : ni Borg ni copie hors de la maison ; RAID 1 et
   instantanés Btrfs seulement, dont la fréquence n'est pas dans le dépôt.
2. **Immich, seule copie hors site** : une archive Borg par nuit ; taille et
   durée d'extraction complète jamais relevées ; aucun test n'extrait les
   originaux en entier.
3. **Hôte Proxmox** : l'installation de l'hôte n'est pas décrite ; la
   restauration de `/etc/pve` depuis Borg n'a jamais été jouée ; la VM n'a
   jamais été restaurée en test, seulement lue.
4. **Scrub Btrfs du NAS** : aucun planifié par le dépôt (choix écrit), aucun n'avait tourné au 05/11 ; planification dans UGOS à vérifier ([sante-des-disques.md](runbooks/sante-des-disques.md)). **Usure et secteurs en attente** des disques : Beszel n'alerte que sur le verdict global ; le rôle `smart_check` (alerte ntfy hebdomadaire sur une hausse, `pve`, Pi, NAS) comble le trou une fois déployé (`pve.yml` et `nas.yml` à la main).
5. **Rangement des clés** : clés age `pro` et `secours`, mot de passe papier
   des KeePass, `backup_passphrase` hors SOPS : lieux non écrits dans le
   dépôt. S'ils sont dans la maison, ils partent avec elle.
6. **`backup_passphrase` unique** : sa perte ferme tous les dépôts Borg et
   les colonnes chiffrées de HealthLog et Dawarich.
7. **Données sans sauvegarde** : démo Keycloak et vitrine de flip (en pause,
   données gardées sur le disque), journal de Promptoramix, miroir kDrive
   (hors Borg).
8. **Le test de restauration ne prouve pas l'appli** : pas de démarrage, pas
   de comparaison au vivant, échantillon de 20 fichiers ≤ 5 Mio, aucun
   contrôle de tous les blocs ; la clé de chiffrement de HealthLog n'est pas
   éprouvée.
9. **Temps de reprise** : une seule reprise mesurée (Pangolin, 45 min). Aucune
   reconstruction complète de la VM docker ni du Pi n'est décrite.
10. **Autres que Sylvain** : aucun document du dépôt ne s'adresse au foyer
    ou à la famille pour reprendre quoi que ce soit. Non vérifié ligne à ligne.
11. **Jours sans nuit réussie** : un dépôt dont le dump échoue chaque nuit
    garde une vieille archive qui se restaure (cas de Nextcloud en octobre
    2026) ; seul le contrôle d'âge du test (28 h) et le moniteur le voient.
12. **Classement** : les étages 1 à 3 de cette page sont une proposition ;
    le dépôt ne dit pas qui utilise quoi, sauf Immich, Wishlist et Jellyfin.
