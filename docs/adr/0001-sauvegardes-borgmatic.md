# 0001. Sauvegardes : Borgmatic et Borg vers la Storage Box, restaurées en CI

- **Statut** : acceptée
- **Date** : 2026-01-16 (Borgmatic), complétée jusqu'au 2026-10-27

## Contexte

Chaque hôte (docker, pi, pangolin, flip, nas) a des données à garder hors
site. Le 07/10/2026, Pangolin entier a cessé de répondre (`SQLITE_BUSY`)
pendant sa sauvegarde : le hook `sqlite_databases` de borgmatic tenait le
verrou de lecture de `db.sqlite` le temps de tout l'envoi.

## Décision

- **Borgmatic + Borg** vers une Hetzner Storage Box, une seule configuration
  partagée (`borgmatic/templates/app.yaml.j2`) appelée par chaque rôle.
- **Un sous-compte Storage Box par hôte** : root d'un hôte ne lit ni ne
  supprime les dépôts d'un autre ; 9 snapshots quotidiens hors de portée.
- **Jamais de dossier de base vivant** : Postgres et MariaDB par dump dans
  leur conteneur, SQLite par le `sqlite3 ".backup"` de l'hôte.
- **Restauration testée en CI** le 1er et le 15 (`restore-test.yaml`),
  `borg check --verify-data` chaque trimestre, en lecture seule.

## Alternatives écartées

- **Restic** (resticprofile vers S3, janvier 2026 ; Borgmatic dès `4a5fb41b`,
  restic retiré au 2026-01-27, `0ed2c98e`) : raison non écrite, à confirmer.
- **Copie à chaud des dossiers de base** : archive incohérente.
- **`sqlite_databases` de borgmatic** : a figé Pangolin (voir Contexte).

## Conséquences

- Restauration prouvée deux fois par mois ; un nouvel hôte demande un
  sous-compte Tofu puis `backup.yaml`.
- La Storage Box ne parle pas S3 ([0013](0013-kubernetes-pas-maintenant.md)).

## Liens

PR #702 (config unique), #715 (SQLite par `.backup`), #817 (sous-comptes),
#760 (test de restauration), #884 (`borg check`) ; [runbooks/sauvegarde-et-restauration.md](../runbooks/sauvegarde-et-restauration.md).
