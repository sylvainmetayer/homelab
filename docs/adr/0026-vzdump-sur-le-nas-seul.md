# 0026. Sauvegardes vzdump sur le NAS seul, sans copie hors site

- **Statut** : acceptée
- **Date** : 2026-10-27 (NAS), 2026-11-02 (risque accepté, QG homelab)

## Contexte

Le job vzdump de Proxmox (VM docker, LXC newt) écrivait sur `local`, la racine de
l'hôte (94 Go). `keep-last=2`, et vzdump écrit la nouvelle archive avant d'élaguer :
trois archives de la VM docker ne tenaient plus. Sa sauvegarde a échoué chaque soir
du 30/09 au 27/10/2026 (« No space left on device »), celle du LXC passait.

## Décision

- **Storage NFS `nas-backup`** (`/volume1/pve-backup`, RAID1), job déclaré dans
  `tofu/proxmox/backup.tf`, 21:00, `keep-last=2`, seule copie des archives.
- **Pas de copie hors site des archives** : accepté le 2026-11-02 ; le motif n'est
  pas écrit, à confirmer. Le hors site reste Borg ([0001](0001-sauvegardes-borgmatic.md)).

## Alternatives écartées

- **`local`** : voir Contexte.

Une copie hors site n'a laissé aucune trace d'étude, seulement l'acceptation.

## Conséquences

- NAS perdu : plus d'image de la VM docker ni du LXC ; seul Borg reste hors site.
- Archives non chiffrées (disque entier de la VM, donc les secrets des applis) :
  dossier sans partage SMB ni autre utilisateur, export pour la seule IP de l'hôte.
- Écritures de la VM ralenties par le NFS pendant le job : fleecing sur `local-lvm`
  depuis #1058.
- Le 2 et le 16 de chaque mois : LXC restauré, archive de la VM vérifiée mais **pas
  restaurée**, faute de disque et de mémoire sur l'hôte (`vzdump_restore_test`).

## Liens

PR #890, #1058 ; [runbooks/sauvegarde-et-restauration.md](../runbooks/sauvegarde-et-restauration.md),
[runbooks/test-restauration-vm.md](../runbooks/test-restauration-vm.md).
