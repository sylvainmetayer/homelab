# vzdump : la VM docker n'est plus sauvegardée

## Symptôme

La sauvegarde vzdump de la VM docker a **échoué chaque soir du 30/09 au
27/10/2026** (« No space left on device ») ; celle du LXC newt passait. Soit
quatre semaines sans nouvelle image de la VM (les deux archives précédentes
restaient, de plus en plus vieilles). Comment cela a été vu : à confirmer
([ADR 0026](../adr/0026-vzdump-sur-le-nas-seul.md) ne le dit pas).

## Cause

Le job écrivait sur `local`, la racine de l'hôte Proxmox (94 Go). Avec
`keep-last=2`, vzdump écrit la nouvelle archive **avant** d'élaguer : trois
archives de la VM docker ne tenaient pas.

## Ce qui a manqué

- Une détection de l'échec du job pendant quatre semaines : le dépôt ne dit
  pas ce qui existait alors, à confirmer.
- Un stockage dimensionné pour trois archives de la VM.
- Encore aujourd'hui : le test du 2 et du 16 (`vzdump_restore_test`) lit
  l'archive de la VM mais **ne la restaure pas**, faute de disque et de mémoire
  sur l'hôte. Une restauration complète n'a jamais été essayée.

## Action

- Storage NFS `nas-backup` sur le NAS (`/volume1/pve-backup`, RAID 1), job de
  21:00 dans `tofu/proxmox/backup.tf`, `keep-last=2` (PR #890 ; fleecing sur
  `local-lvm`, PR #1058).
- **Risque accepté le 02/11/2026** : pas de copie hors site des archives. Le
  NAS perdu, plus aucune image de la VM ni du LXC ; seul Borg reste
  ([matrice des données](../matrice-des-donnees.md)). Le motif : à confirmer.
- Test de restauration :
  [test-restauration-vm.md](../runbooks/test-restauration-vm.md).

Sources : [ADR 0026](../adr/0026-vzdump-sur-le-nas-seul.md) ;
[sauvegarde-et-restauration.md](../runbooks/sauvegarde-et-restauration.md).
