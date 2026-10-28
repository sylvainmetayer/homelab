# 0007. NAS : données d'applis en NFSv3, Jellyfin sur le NAS, relais du 443

- **Statut** : acceptée
- **Date** : 2026-10-26 (NFS), 2026-10-27 (Jellyfin), 2026-10-28 (relais du 443)

## Contexte

On veut une VM docker remplaçable, sans donnée à perdre. Le NAS Ugreen
(UGOS Pro) a les disques, les médias et le GPU qu'il faut à Jellyfin ; son
nginx tient les ports 80 et 443.

## Décision

- **Données d'applis sur le NAS** en NFSv3, export `sync`, montage `hard` +
  automount (rôle `nas_storage`, pilote `nginx_demo`) ; Borg sauvegarde tout.
- **SQLite (et toute base mmap/verrous) jamais sur NFS** : disque local.
- **Jellyfin sur le NAS** (`dc@jellyfin` système), privé : LAN, ou client
  Pangolin par le site `nas`. `nas_proxy` (Traefik, DNS-01 OVH) termine le
  TLS en `:8443` ; un **relais en réseau hôte** (`nas-proxy-443`, TCP brut +
  PROXY v2) tient le 443 de l'hôte : les URL marchent sans port.

## Alternatives écartées

- **NFSv4.1** : UGOS 1.20 ne l'exporte pas (activable en SSH, non supporté).
- **iSCSI + LVM** : étape Proxmox manuelle, LUN opaque, ext4 en lecture seule
  à la moindre panne du NAS.
- **Volume Docker `driver_opts: nfs`** : Borg ne le lit pas.
- **`443:443` publié sur `nas-proxy`** : si UGOS reprend le 443, Docker
  refuse de créer le conteneur et le 8443 tombe avec lui.

## Conséquences

- Un NAS absent retient ses applis (attente bornée `nas-storage-wait`).
- Si une mise à jour d'UGOS recoche sa redirection HTTPS, l'URL sans port
  casse à la maison ; `--tags nas_proxy` échoue en le disant.

## Liens

PR #412 (NFS), #860 (Jellyfin), #893 (`nas_proxy`), #904 (relais du 443) ;
`nas-storage-docker/homelab-storage-architecture.md`, [media.md](../media.md).
