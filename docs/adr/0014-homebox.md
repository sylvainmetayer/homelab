# 0014. Homebox : disque local, derrière le SSO, inscription fermée par variable

- **Statut** : acceptée
- **Date** : 2026-10-28

## Contexte

Un inventaire de la maison :
[Homebox](https://homebox.software/), fork maintenu `sysadminsmedia`. Sa
base est en SQLite, et il n'a ni commande de création de compte ni exception
pour le premier compte : l'inscription est ouverte à tous ou fermée.

## Décision

- Un seul conteneur (`dc@homebox`, `-rootless`), données sur le **disque
  local** de la VM docker ; base copiée par `sqlite3 .backup`.
- `homebox.sylvain.cloud` **derrière le SSO**, FR/DE, aucun chemin ouvert.
- **Inscription fermée** (`homebox_allow_registration: false`), ouverte le
  temps d'un passage Ansible (`-e homebox_allow_registration=true`) ; les
  comptes suivants passent par une invitation de groupe.
- Le poivre des clés d'API est dérivé de `backup_passphrase` : aucun
  nouveau secret SOPS.

## Alternatives écartées

- **Données sur le NAS** : SQLite n'y va jamais ([0007](0007-donnees-sur-le-nas.md)) ;
  les pièces jointes restent à côté d'elle, dans le même `data/`.
- **Inscription ouverte en permanence** : derrière le SSO le risque est
  faible, mais rien ne la justifie après le premier compte.

## Conséquences

- Créer le premier compte demande trois étapes manuelles (ouvrir, s'inscrire,
  refermer).
- Le test de restauration échoue sur `homebox` jusqu'à sa première archive.

## Liens

PR #921 ; `ansible/roles/homebox/defaults/main.yml`.
