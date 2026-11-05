# Santé des disques : S.M.A.R.T., usure, scrub Btrfs

Ce qui prévient avant qu'un disque ne meure (NAS, SSD de l'hôte Proxmox), ce
qui ne prévient pas, et les contrôles à faire à la main. Une fois le disque
mort : [disque-nas-mort.md](disque-nas-mort.md),
[hote-proxmox-mort.md](hote-proxmox-mort.md).

Écrit le 05/11/2026 depuis le dépôt et le code de Beszel 0.21.1 (version de
l'image du hub). Rien ici n'a été relevé sur un hôte : ce qui touche le
matériel, UGOS ou l'interface de Beszel est marqué « à vérifier ».

## Ce que le dépôt fait déjà

| Hôte | Disques lus par l'agent Beszel | Déclaré dans |
|---|---|---|
| `nas` | `sda` et `sdb` (WD40EFZZ, la paire du RAID 1), `sdc` (WD30EZRX en USB) | `host_vars/nas` |
| `pve` | `sda`, le SSD M.2 SATA qui porte l'hôte, `local-lvm` et donc **tout** le disque de la VM docker | `pve.yml` |
| `pi` | le NVMe derrière un pont USB : peut ne rien remonter | `host_vars/pi` |

La VM docker, flip, Pangolin et le LXC ne voient qu'un disque virtuel : leur
usure se lit sur `pve` (ou chez Hetzner). Les autres hôtes n'ont rien à lire.

**Alerte automatique.** Beszel prévient quand l'état d'un disque **empire**
(`PASSED` vers `WARNING` ou `FAILED`, `internal/alerts/alerts_smart.go`), sans
rien à déclarer dans `beszel_alerts` ni seuil à régler. Le message part aux
utilisateurs du système (`config.yml` : le compte administrateur) par leurs
canaux : l'e-mail (SMTP réglé dans l'interface du hub) et Telegram, **qui
n'existe pas encore** (clés SOPS `beszel_telegram_bot_token` et
`beszel_telegram_chat_id` absentes, [README du rôle](../../ansible/roles/beszel/README.md)).
Un disque `UNKNOWN` (illisible) ne déclenche rien.

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

Lecture seule, en root sur `pve`, avec `sudo` sur le NAS (`smartctl` y est :
à vérifier ; l'agent Beszel du NAS emporte le sien).

```bash
smartctl -H -A /dev/sda    # sur chaque disque : sda, sdb, sdc au NAS ; sda sur pve
```

| Disque | À lire | Remplacer ou racheter quand |
|---|---|---|
| NAS (HDD) | 5 `Reallocated_Sector_Ct`, 197 `Current_Pending_Sector`, 198 `Offline_Uncorrectable` ; 199 `UDMA_CRC_Error_Count` (câble) | l'un des trois premiers est supérieur à 0 **et croît** d'un contrôle à l'autre |
| `pve` (SSD SATA) | l'attribut d'usure du modèle : 177 `Wear_Leveling_Count`, 202, 231 ou 233 (valeur normalisée, 100 neuf, qui descend) | normalisée sous 20 : racheter ; sous 10 : sans attendre. Le modèle n'est pas dans le dépôt : à vérifier |

Noter la date et les valeurs en bas de ce fichier (« Relevés »), pour voir la
pente. Une pente vaut mieux qu'un seuil.

## Scrub Btrfs du NAS

UGOS n'est pas géré par le dépôt (aucune modification système d'UGOS) : le rôle
`nas` ne touche que les réglages NFS. **Pas de timer posé par le dépôt**, parce
qu'un `btrfs scrub` programmé de l'extérieur ajoute une unité systemd au système
d'UGOS, peut doubler un scrub qu'UGOS programme déjà, et qu'on ne sait pas
(à vérifier) si le RAID 1 est celui de Btrfs ou un `md` sous Btrfs, ce qui change
ce que le scrub répare.

**À vérifier dans UGOS** (menu à chercher : stockage, volume `volume1`,
maintenance ou vérification) :

1. Existe-t-il un scrub planifié du volume, et quand a-t-il tourné la dernière
   fois ? S'il y en a un, **ne rien ajouter**.
2. Sinon, le lancer à la main un dimanche en journée et le planifier si UGOS le
   permet. Éviter 21:00 (vzdump), 02:30 (borgmatic) et 04:00 (kDrive) : le scrub
   lit tout le volume et ralentit les trois.

Lecture seule, sur le NAS, pour constater (sans rien lancer) :

```bash
sudo btrfs scrub status /volume1   # dernier scrub, erreurs trouvées et corrigées
sudo btrfs device stats /volume1   # tous les compteurs doivent être à 0
```

Des compteurs non nuls, ou des erreurs non corrigeables, valent une alerte :
copier ce qui compte, puis [disque-nas-mort.md](disque-nas-mort.md). Si le RAID 1
est un `md` sous Btrfs, le scrub **détecte** une corruption mais ne la répare
pas depuis le second disque : la vérification du RAID (`md`) est l'affaire
d'UGOS, à vérifier aussi.

## Ce qui reste à décider

Une alerte sur l'**usure** et les **secteurs en attente**, que Beszel n'offre
pas. La forme la plus petite : un script `smartctl -j` lancé chaque semaine par
un timer sur `pve` et sur le NAS, qui publie sur ntfy (comme `update_notify`) et
pousse un moniteur Uptime Kuma. Non fait ici : il demande un moniteur dans
`tofu/pangolin_config`, une URL push dans SOPS (dépôt `homelab-secrets`) et, sur
le NAS, un timer posé à la main (`nas.yml` ne passe jamais en CI). À lancer
quand Sylvain le décide ; d'ici là, le contrôle trimestriel ci-dessus.

## Relevés

(vide : premier relevé à faire)
