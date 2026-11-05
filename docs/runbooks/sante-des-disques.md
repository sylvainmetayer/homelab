# Santé des disques : S.M.A.R.T., usure, scrub Btrfs

Ce qui prévient avant qu'un disque ne meure (NAS, SSD de l'hôte Proxmox), ce
qui ne prévient pas, et les contrôles à faire à la main. Une fois le disque
mort : [disque-nas-mort.md](disque-nas-mort.md),
[hote-proxmox-mort.md](hote-proxmox-mort.md).

Écrit le 05/11/2026 depuis le dépôt et le code de Beszel 0.21.1 (version de
l'image du hub). Hors de la section « Relevés », rien ici n'a été relevé sur un
hôte : ce qui touche le matériel, UGOS ou l'interface de Beszel est marqué « à
vérifier ».

## Ce que le dépôt fait déjà

| Hôte | Disques lus par l'agent Beszel | Déclaré dans |
|---|---|---|
| `nas` | `sda` et `sdb` (WD40EFZZ, la paire du RAID 1), `sdc` (WD30EZRX en USB) | `host_vars/nas` |
| `pve` | `sda`, le SSD M.2 SATA qui porte l'hôte, `local-lvm` et donc **tout** le disque de la VM docker | `pve.yml` |
| `pi` | le NVMe derrière un pont USB : peut ne rien remonter | `host_vars/pi` |

La VM docker, flip, Pangolin et le LXC ne voient qu'un disque virtuel : leur
usure se lit sur `pve` (ou chez Hetzner). Les autres hôtes n'ont rien à lire.

**Alerte automatique.** Beszel prévient quand l'état d'un disque **empire**
depuis `PASSED` (`internal/alerts/alerts_smart.go`), sans rien à déclarer dans
`beszel_alerts` ni seuil à régler. En 0.21.1 l'état ne prend que les valeurs
`PASSED`, `FAILED` et `UNKNOWN` (`agent/smart_parse.go`) : l'alerte réelle est
`PASSED` vers `FAILED`, le `WARNING` du code d'alerte n'est jamais produit.
Le disque est relu toutes les heures par défaut : l'alerte peut arriver une
heure après le verdict. Le message part aux
utilisateurs du système (`config.yml` : le compte administrateur) par leurs
canaux : l'e-mail (SMTP réglé dans l'interface du hub) et Telegram, **qui
n'existe pas encore** (clés SOPS `beszel_telegram_bot_token` et
`beszel_telegram_chat_id` absentes, [README du rôle](../../ansible/roles/beszel/README.md)).
Un disque `UNKNOWN` (illisible) ne déclenche rien, et un disque qui passe
d'`UNKNOWN` à `FAILED`, ou qui apparaît déjà `FAILED`, non plus : seule la
transition depuis `PASSED` prévient. Un système en sourdine dans l'interface
(notifications silencieuses) ne reçoit rien.

À côté : l'alerte `Temperature` (80 °C sur 10 min) sur `nas`, `pi`, `pve`, et
`Status` (hôte muet 5 min) partout.

## Ce que Beszel ne fait pas

L'état d'un disque est le verdict global de `smartctl` (`agent/smart_parse.go`).
Donc :

- **Pas d'alerte sur l'usure.** Le pourcentage utilisé d'un SSD est affiché
  parmi les attributs, pas surveillé. Un SSD SATA ne passe en `FAILED` que
  lorsque l'attribut d'usure franchit le seuil du constructeur : tard.
- **Pas d'alerte sur les secteurs réalloués, en attente ou non corrigeables**
  d'un disque dur : un WD Red peut en accumuler en restant `PASSED`.
- **Rien si le disque n'est pas lu** (pont USB sans passage SMART, permission) :
  il faut le voir dans la page S.M.A.R.T. du système.

Aucun réglage du rôle ne comble cela : les alertes du rôle sont les types du
hub, et il n'en existe pas pour les attributs. C'est le seul trou, voir la fin.

## À régler dans l'interface de Beszel (https://monitoring.sylvain.cloud)

À faire une fois, puis après un changement de disque. Rien ne se pose par
Ansible, et le dépôt ne peut pas le vérifier.

1. **Un canal qui arrive.** Réglages, notifications : le SMTP fonctionne
   (envoyer le message de test) ; sinon un SMTP absent rend l'alerte S.M.A.R.T.
   muette. À vérifier.
2. **Les disques sont lus.** Pages S.M.A.R.T. de `nas` (trois disques) et de
   `pve` (un disque), état `PASSED`, modèle et température renseignés. Un disque
   absent ou `UNKNOWN` ne préviendra jamais ; pour le pont USB de `sdc`,
   `smartctl` peut exiger un type (`beszel_agent_smart_devices`, champ `type`).
3. **Le système a bien un utilisateur** (le compte administrateur) : il vient de
   `config.yml`, rien à faire sauf si l'interface montre un système sans
   utilisateur.

## Contrôle trimestriel à la main (usure, secteurs)

Lecture seule, en root sur `pve`, avec `sudo` sur le NAS (`/usr/sbin/smartctl` y est, relevé le
05/11/2026 ; l'agent Beszel du NAS emporte le sien : à vérifier).

```bash
smartctl -H -A /dev/sda    # sur chaque disque : sda, sdb, sdc au NAS (sdc s'il est revenu) ; sda sur pve
smartctl -H -A -d sntrealtek /dev/sda   # sur le Pi (voir sa ligne ci-dessous)
```

| Disque | À lire | Remplacer ou racheter quand |
|---|---|---|
| NAS (HDD ; `sdc` fait exception, voir « Relevés ») | 5 `Reallocated_Sector_Ct`, 197 `Current_Pending_Sector`, 198 `Offline_Uncorrectable` (valeur brute, `RAW_VALUE`) ; 199 `UDMA_CRC_Error_Count` (câble) | 197 ou 198 supérieur à 0 : copier ce qui compte et remplacer le disque, sans attendre qu'il croisse. 5 supérieur à 0 **et en hausse** d'un contrôle à l'autre : idem. 199 en hausse : changer le câble ou le pont USB |
| `pve` (SSD SATA) | l'attribut d'usure du modèle : 177 `Wear_Leveling_Count`, 173, 169, 202, 231 ou 233 (valeur **normalisée** `VALUE`, 100 neuf, qui descend ; sur certains modèles le brut est le pourcentage déjà consommé, lire le nom de l'attribut) ; 232 `Available_Reservd_Space` | normalisée sous 20 : racheter ; sous 10 : sans attendre. Le modèle n'est pas dans le dépôt (SSD 512 Go, usure à 100 au premier relevé) |
| `pi` (NVMe, pont USB) | `smartctl -H -A -d sntrealtek /dev/sda` : `Percentage Used`, `Available Spare`, `Media and Data Integrity Errors` | `Percentage Used` au-delà de 80 : racheter ; `Available Spare` sous 20 ou erreurs d'intégrité non nulles : sans attendre. Si le pont ne remonte rien, ce contrôle est le seul |

Noter la date et les valeurs en bas de ce fichier (« Relevés »), pour voir la
pente. Une pente vaut mieux qu'un seuil.

## Scrub Btrfs du NAS

UGOS n'est pas géré par le dépôt (aucune modification système d'UGOS) : le rôle
`nas` ne touche que les réglages NFS. **Pas de timer posé par le dépôt**, parce
qu'un `btrfs scrub` programmé de l'extérieur ajoute une unité systemd au système
d'UGOS, peut doubler un scrub qu'UGOS programme déjà, et que le RAID 1 est
un `md` sous Btrfs (`md1`, puis LVM, voir « Relevés »), ce
qui change ce que le scrub répare.

**À vérifier dans UGOS** (menu à chercher : stockage, volume `volume1`,
maintenance ou vérification) :

1. Existe-t-il un scrub planifié du volume, et quand a-t-il tourné la dernière
   fois ? S'il y en a un, **ne rien ajouter**.
2. Sinon, le lancer à la main un dimanche en journée et le planifier si UGOS le
   permet. Éviter 21:00 (vzdump), 02:30 (borgmatic), 04:00 (kDrive) et
   10:00 les 2 et 16 du mois (test de restauration vzdump, qui relit l'archive
   sur le NAS) : le scrub lit tout le volume et ralentit les quatre.

Lecture seule, sur le NAS, pour constater (sans rien lancer) :

```bash
sudo btrfs scrub status /volume1   # dernier scrub, erreurs trouvées et corrigées
sudo btrfs device stats /volume1   # tous les compteurs doivent être à 0
```

Des compteurs non nuls, ou des erreurs non corrigeables, valent une alerte :
copier ce qui compte, puis [disque-nas-mort.md](disque-nas-mort.md). Le RAID 1 étant
un `md` sous Btrfs, le scrub **détecte** une corruption mais ne la répare
pas depuis le second disque : la vérification du RAID (`md`) est l'affaire
d'UGOS, à vérifier aussi (`cat /proc/mdstat` : `[UU]` tant que les deux disques sont là).

## Ce qui reste à décider

Une alerte sur l'**usure** et les **secteurs en attente**, que Beszel n'offre
pas. La forme la plus petite : un script `smartctl -j` lancé chaque semaine par
un timer sur `pve` et sur le NAS, qui publie sur ntfy (comme `update_notify`) et
pousse un moniteur Uptime Kuma. Non fait ici : il demande un moniteur dans
`tofu/pangolin_config`, une URL push dans SOPS (dépôt `homelab-secrets`) et, sur
le NAS, un timer posé à la main (`nas.yml` ne passe jamais en CI). À lancer
quand Sylvain le décide ; d'ici là, le contrôle trimestriel ci-dessus.

## Relevés

**05/11/2026.** Valeurs brutes, heures de marche entre parenthèses.

| Disque | Réalloués (5) | En attente (197) | Non corrigeables (198) | CRC (199) | Temp. | Remarque |
|---|---|---|---|---|---|---|
| NAS `sda` WD40EFZZ (1662 h) | 0 | 0 | 0 | 0 | 41 °C | |
| NAS `sdb` WD40EFZZ (1678 h) | 0 | 0 | 0 | 0 | 39 °C | lien SATA négocié à 3 Gb/s au lieu de 6 |
| NAS `sdc` WD30EZRX, USB (5199 h) | | **2167** | **2031** | | 32 °C | **défaillant** |
| `pve` `sda` SSD 512 Go (13 258 h) | 0 | | | | 53 °C | usure normalisée (177) à 100 |
| `pi` NVMe | | | | | | non lu : `smartctl` absent du Pi, à installer à la main avant le contrôle trimestriel |

`sdc` dépasse largement le seuil de remplacement sans que Beszel prévienne,
comme attendu plus haut : c'est exactement le trou décrit dans « Ce qui reste à
décider ». Il ne porte que 680 Mo. Décision du 05/11/2026 : il reste branché,
mais rien ne doit compter sur lui, aucune copie ni sauvegarde (la règle « remplacer
le disque » du contrôle trimestriel ne s'applique donc pas à lui).

Volume `/volume1` : `btrfs scrub status` répond « no stats available », aucun
scrub n'a donc tourné ; `btrfs device stats` est à 0 partout. Le RAID 1 est un `md` : `lsblk` montre
`sda2` et `sdb2` en `md1` (raid1, `[UU]` dans `/proc/mdstat`), puis LVM
(un volume logique `…-volume1`), puis Btrfs monté sur `/volume1`. Un scrub détecte donc
une corruption des données sans la réparer depuis l'autre disque.

**`sdc` a décroché du bus USB le 05/11/2026 à 16:13** (heure du NAS, journal du noyau :
`tag#0 timing out command, waited 30s`, puis `usb 4-2: USB disconnect`). Au
relevé suivant, `lsblk` ne le listait plus. Cause non établie.
