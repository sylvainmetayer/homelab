# Coupure de courant : exercice et retour du secteur

Aucun onduleur aujourd'hui : une coupure éteint d'un coup le NAS, l'hôte
Proxmox, le Pi et la Bbox. Ce fichier sert à prouver à froid que tout revient
seul, avant que ça n'arrive pour de vrai. Procédure, pas un incident ; une
vraie coupure : aller directement à « Au retour du secteur ».

Écrit le 05/11/2026. **Jamais joué** : aucun démarrage à froid après coupure
n'est prouvé sur ces machines. Noter le résultat en bas de ce fichier.

## Ce qui est établi, et ce qui ne l'est pas

| Point | État |
|---|---|
| VM docker et LXC démarrent avec l'hôte | oui : `onboot: 1` sur les deux, relevé le 05/11 |
| Ordre de démarrage | LXC : `order=3, up=60, down=60`. VM : aucun ordre déclaré |
| Applis de la VM | reviennent seules : unités `dc@` lancées après Docker |
| Montages NFS de `nas_storage` | `nofail,_netdev,x-systemd.automount` : rien n'attend le NAS au démarrage |
| Stockage `nas-backup` de Proxmox | NFS `vers=3`. Si le NAS revient après l'hôte : à observer |
| Hôte Proxmox : redémarre seul au retour du courant | **à vérifier dans le BIOS** (« Restore on AC Power Loss », voir la mise en garde sous l'exercice) |
| NAS DXP2800 : redémarre seul au retour du courant | **à vérifier dans le BIOS** ; son dernier redémarrage ne coupait pas le courant, il ne prouve donc rien |
| Pi | démarre à la mise sous tension (comportement du matériel, à observer) |
| Bbox | se rallume seule en général, à observer |
| DNS pendant le retour | le DHCP annonce Blocky (LXC et Pi) : à observer tant qu'ils ne sont pas revenus |

## Exercice

À jouer un soir où personne ne dépend du réseau ni de Jellyfin. Éviter 21:00
(vzdump), 01:00 et 02:30 (borgmatic), 04:00 (kDrive), et 10:00 les 2 et 16 du
mois (test de restauration vzdump). Le timer `kdrive-sync` est `Persistent` :
après un long arrêt, il lance sa copie dès le démarrage.

**On n'arrache pas le courant à des machines allumées.** L'exercice arrête tout
proprement, coupe hors tension, puis observe le démarrage à froid : c'est lui
qu'on veut prouver, sans risquer le RAID 1 du NAS ni la VM de l'hôte.

Avant de commencer, noter l'heure et, si possible, la consommation mesurée à la
prise : la charge totale n'est qu'une estimation (55 à 80 W, pointe vers 100 W).

| # | Action | Noter | Réussi si |
|---|---|---|---|
| 1 | Regarder les moniteurs « Backup … » dans Uptime Kuma | l'heure du dernier succès | tous verts |
| 2 | Arrêter l'hôte Proxmox : VM et LXC s'arrêtent avec lui | durée | moins de 3 min, aucun invité en erreur |
| 3 | Arrêter le NAS | durée | volume démonté proprement |
| 4 | Arrêter le Pi en dernier | durée | pas de vérification de disque au démarrage suivant |
| 5 | Couper au mur pendant 2 min | heure | tout est éteint |
| 6 | Rétablir le courant, **sans rien allumer à la main** | heure de démarrage de chaque machine | les quatre démarrent seules |
| 7 | `qm list`, `pct list`, `pvesm status` sur l'hôte ; `docker ps` sur la VM et le Pi | ce qui manque | tout revient en moins de 20 min, `nas-backup` actif |
| 8 | Page des disques de Beszel, `smartctl -A` sur chaque disque | écart avec les [relevés](sante-des-disques.md) | aucune nouvelle erreur |
| 9 | Ouvrir `photos.sylvain.cloud` et une appli derrière le SSO | temps jusqu'au retour | accès rétabli, sites Newt en ligne |

Une machine qui ne démarre pas seule à l'étape 6 : corriger son réglage dans le
BIOS, puis rejouer les étapes 5 et 6.

**Limite de l'exercice.** Une machine arrêtée proprement puis privée de courant
se comporte comme sur le réglage « Power On », pas comme après une vraie
coupure : avec « Last State » (dernier état), elle reste éteinte, alors qu'une
coupure subie allumée la relancerait. Lire donc le réglage dans le BIOS
(« Power On » ou « Last State »), sans se fier au seul résultat de l'étape 6 ;
si c'est « Last State », l'exercice ne prouve rien pour cette machine.

## Au retour du secteur

1. Attendre vingt minutes avant de conclure quoi que ce soit : la Bbox, les
   hôtes et les applis reviennent à leur rythme.
2. Allumer à la main ce qui n'a pas démarré, dans cet ordre : Bbox, NAS, hôte
   Proxmox, Pi.
3. Dérouler les étapes 7 à 9 ci-dessus.
4. Plus de DNS sur le réseau : [dns-blocky.md](dns-blocky.md).
5. Les sauvegardes manquées repartent à leur prochain créneau : vérifier les
   moniteurs le lendemain ([sauvegarde-et-restauration.md](sauvegarde-et-restauration.md)).

## Prévention

Pas d'onduleur pour l'instant, décision du 05/11/2026 : on prouve d'abord le
retour à froid. Si un onduleur arrive, il faudra une ADR, un rôle NUT et une
section ici. Le disque USB `sdc` du NAS ne compte pas : il est défaillant et
gardé sans y compter ([relevés](sante-des-disques.md)).

## Résultats

(vide : exercice jamais joué)
