# Coupure de courant : exercice et retour du secteur

Aucun onduleur aujourd'hui : une coupure éteint d'un coup le NAS, l'hôte
Proxmox, le Pi et la Bbox. Ce fichier sert à prouver à froid que tout revient
seul, avant que ça n'arrive pour de vrai. Procédure, pas un incident ; une
vraie coupure : aller directement à « Au retour du secteur ».

Écrit le 05/11/2026. L'exercice n'a **jamais été joué**, mais une vraie coupure
a eu lieu le 17/11/2026 (« Résultats ») : le NAS et le Pi sont revenus seuls,
**pas l'hôte Proxmox**. Noter le résultat de chaque passage en bas de ce fichier.

## Ce qui est établi, et ce qui ne l'est pas

| Point | État |
|---|---|
| VM docker et LXC démarrent avec l'hôte | oui : `onboot: 1` sur les deux, relevé le 05/11 |
| Ordre de démarrage | LXC : `order=3, up=60, down=60`. VM : aucun ordre déclaré |
| Applis de la VM | reviennent seules : unités `dc@` lancées après Docker |
| Montages NFS de `nas_storage` | `nofail,_netdev,x-systemd.automount` : rien n'attend le NAS au démarrage |
| Stockage `nas-backup` de Proxmox | NFS `vers=3`. Si le NAS revient après l'hôte : à observer |
| Hôte Proxmox : redémarre seul au retour du courant | **non** (coupure du 17/11) : resté éteint, rallumé à distance par Wake-on-LAN. **À corriger dans le BIOS**, sur place (« À faire sur place » plus bas) |
| Hôte Proxmox : Wake-on-LAN | marche (17/11) : le secours tant que le BIOS n'est pas corrigé, et après |
| NAS DXP2800 : redémarre seul au retour du courant | oui (coupure du 17/11) |
| Pi | oui (coupure du 17/11) : démarre à la mise sous tension |
| Bbox | se rallume seule en général, à observer |
| DNS pendant le retour | le DHCP est censé annoncer Blocky (LXC et Pi ; aucun client constaté au 05/11, [ADR 0012](../adr/0012-filtrage-dns-blocky.md)) : à observer tant qu'ils ne sont pas revenus |

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
| 8 | Page des disques de Beszel, `smartctl -A` sur chaque disque, `cat /proc/mdstat` au NAS | écart avec les [relevés](sante-des-disques.md) | aucune nouvelle erreur, `md1` en `[UU]` et sans ligne `resync` ou `recovery` ; `sdc` peut manquer (décroché le 05/11) |
| 9 | Ouvrir `photos.sylvain.cloud` et une appli derrière le SSO | temps jusqu'au retour | accès rétabli, sites Newt en ligne |

Une machine qui ne démarre pas seule à l'étape 6 : corriger son réglage dans le
BIOS, puis rejouer les étapes 5 et 6.

**Limite de l'exercice.** Une machine arrêtée proprement puis privée de courant
se comporte comme sur le réglage « Power On », pas comme après une vraie
coupure : avec « Last State » (dernier état), elle reste éteinte, alors qu'une
coupure subie allumée la relancerait. Lire donc le réglage dans le BIOS
(« Power On » ou « Last State »), sans se fier au seul résultat de l'étape 6 ;
si c'est « Last State », l'exercice ne prouve rien pour cette machine.

## À faire sur place : le BIOS de l'hôte Proxmox

Aucun réglage du dépôt ne rallume une machine éteinte : c'est le BIOS du mini
PC qui décide, et il ne se change qu'avec un écran et un clavier (pas d'IPMI).

1. Arrêter l'hôte proprement (un soir, hors des créneaux de l'exercice), le
   rallumer en entrant dans le BIOS.
2. Chercher « Restore on AC Power Loss » (aussi « AC Power Recovery », « After
   Power Failure », « State After G3 », souvent sous Power, Chipset ou ACPI) et
   le passer à **« Power On »**. Pas « Last State » : après un arrêt propre
   suivi d'une coupure, la machine resterait éteinte.
3. Laisser le Wake-on-LAN activé au même endroit (« Wake on LAN », « Power On
   by PCI-E »), et couper « ErP » ou « Deep Sleep » s'il existe : il coupe
   l'alimentation de veille, donc le réveil par le réseau et parfois le retour
   automatique.
4. Prouver : étapes 2, 5 et 6 de l'exercice pour l'hôte seul (arrêt, coupure au
   mur 2 min, retour du courant sans toucher au bouton).
5. Noter le résultat ci-dessous et corriger la ligne du tableau.

## Au retour du secteur

1. Attendre vingt minutes avant de conclure quoi que ce soit : la Bbox, les
   hôtes et les applis reviennent à leur rythme.
2. Allumer ce qui n'a pas démarré, dans cet ordre : Bbox, NAS, hôte
   Proxmox, Pi. À distance, l'hôte Proxmox se réveille par Wake-on-LAN depuis
   une machine du réseau local déjà revenue (le 17/11, c'est ce qui l'a
   relancé).
3. Dérouler les étapes 7 à 9 ci-dessus.
4. Plus de DNS sur le réseau : [dns-blocky.md](dns-blocky.md).
5. Les sauvegardes manquées repartent à leur prochain créneau : vérifier les
   moniteurs le lendemain ([sauvegarde-et-restauration.md](sauvegarde-et-restauration.md)).

## Prévention

Pas d'onduleur pour l'instant, décision du 05/11/2026 : on prouve d'abord le
retour à froid. Si un onduleur arrive, il faudra une ADR, un rôle NUT et une
section ici. Le disque USB `sdc` du NAS ne compte pas : il est défaillant et
gardé sans y compter ; il a décroché du bus USB le 05/11/2026 à 16:13
([relevés](sante-des-disques.md)).

## Résultats

| Date | Quoi | Résultat |
|---|---|---|
| 17/11/2026 | Vraie coupure de courant (pas l'exercice) | NAS et Pi revenus seuls. Hôte Proxmox resté éteint, rallumé à distance par Wake-on-LAN ; VM docker et LXC ont suivi (`onboot`). ntfy, alors sur la VM docker, était muet : déplacé sur la VM Pangolin ([ADR 0037](../adr/0037-ntfy-sur-la-vm-pangolin.md)). Reste à faire : le BIOS de l'hôte (« À faire sur place »). Étapes 7 à 9 non relevées. |
