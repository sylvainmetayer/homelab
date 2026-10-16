# Test de restauration des dépôts borg

`.github/workflows/restore-test.yaml` (le 1er et le 15 du mois, ou à la main)
restaure la dernière archive de chaque dépôt de `apps.json` sur un runner
GitHub, loin des hôtes qui la produisent (issue #444) :

- dumps PostgreSQL rejoués (`pg_restore`) dans un conteneur jetable de l'image
  de la base du rôle, MySQL/MariaDB (`mariadb`) de même ;
- copies SQLite (`/var/lib/borgmatic-sqlite/<dépôt>/`) passées à
  `PRAGMA integrity_check` ;
- pour tous, un échantillon de fichiers extrait (borg vérifie chaque bloc en
  le déchiffrant) ;
- puis une table au moins dans chaque base restaurée.

Le résultat part sur le moniteur Uptime Kuma « Restore test <app> »
(`tofu/pangolin_config`, intervalle 20 jours : le provider plafonne à 24).

## Accès

Le sous-compte Storage Box `restore-test` (`tofu/pangolin/storage_box.tf`)
est **en lecture seule** et enfermé dans le dossier des dépôts : sa clé, dans
les secrets Actions, ne peut rien supprimer. borg 1.x pose un verrou même pour
lire, d'où `--bypass-lock` ; le workflow tourne à 10:00 UTC, loin des
sauvegardes de 01:00. Sa clé publique est déposée dans
`<dossier des dépôts>/.ssh/authorized_keys` par `ansible/backup.yaml`.

## `apps.json`

Clé : celle du moniteur (entrée de `local.websites`, ou `pangolin`), que
`tofu/pangolin_config/tests/invariants.tftest.hcl` compare aux moniteurs.

- `repo` : dossier du dépôt sur la Storage Box (`backup_folders`) et
  `borgmatic_app_name` (dossier de staging SQLite) ;
- `role` : rôle Ansible dont le `compose.yaml` donne l'image de la base ;
- `passphrase_key` : clé de `ansible/secrets.sops.yaml` si le rôle en lit une
  autre que `backup_passphrase` (elle y retombe si la clé est absente).

Une app ajoutée avec `backup = true` doit y entrer, sinon `tofu test` échoue.

## Lancer à la main

Actions → « Restore test » → Run workflow ; `apps` restreint à une liste
(`betisier,rss`).
