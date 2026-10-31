# 0020. Garder le Raspberry Pi pour Immich

- **Statut** : acceptée
- **Date** : 2026-10-31

## Contexte

Immich, le service le plus utilisé de la famille, tourne sur un Raspberry Pi 4
(3,8 Go, SSD USB, pas de carte SD ; `ansible/pi.yml`), avec Blocky, son propre
Newt et son propre sous-compte borgmatic. Tout le reste du LAN est sur Proxmox :
la VM docker (3 cœurs, 12 Gio, SSD SATA d'entrée de gamme, l'I/O y est déjà le
goulot) et le LXC newt.

## Décision

Garder le Pi : Immich reste hors de Proxmox et de la VM docker. Une panne, une
charge ou une maintenance de Proxmox ne coupe pas les photos, et l'inverse.

## Alternatives écartées

- **Absorber le Pi dans Proxmox (VM ou LXC)** : un hôte de moins à tenir et un
  CPU plus fort, mais Immich partagerait le disque et l'arrêt de Proxmox, et
  les deux Blocky (Pi et LXC) deviendraient dépendants du même hôte.

## Conséquences

- Isolation : Immich publié par le Newt du Pi, sauvegardé par son borgmatic ;
  Blocky garde une instance hors Proxmox.
- Un hôte physique de plus : mises à jour, redémarrage de 05:30, S.M.A.R.T.
  par un pont USB RTL9210 non vérifié, pas de vzdump (borgmatic seul).
- CPU faible : les gros travaux (vignettes, ML) passent par un worker distant
  à la main (`compose/immich/README.md`) ; mémoire par conteneur absente tant
  que le cgroup mémoire est coupé (#846).
- Le déploiement CI atteint le Pi par le LXC newt (`pi.internal`) : il dépend
  de Proxmox, Immich non.

## Liens

`ansible/pi.yml`, `ansible/host_vars/pi/variables.yaml` ;
`docs/architecture.md` ; [0012](0012-filtrage-dns-blocky.md).
