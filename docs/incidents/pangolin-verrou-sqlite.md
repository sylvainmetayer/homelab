# Pangolin figé par sa propre sauvegarde

## Symptôme

Le **07/10/2026**, Pangolin entier a cessé de répondre (`SQLITE_BUSY`) pendant
sa sauvegarde. Heure et durée : à confirmer.

## Cause

Le hook `sqlite_databases` de borgmatic tenait le verrou de lecture de
`db.sqlite` pendant tout l'envoi vers la Storage Box
([ADR 0001](../adr/0001-sauvegardes-borgmatic.md)). Plus la base est grosse,
plus l'envoi dure : la rétention des journaux de Pangolin valait 9001 jours,
donc la base ne faisait que grossir ([ADR 0005](../adr/0005-retention-journaux-pangolin.md)).

## Ce qui a manqué

- Une règle pour les bases SQLite vivantes : ni copie à chaud (archive
  incohérente), ni hook qui garde un verrou le temps de l'envoi. Elle n'est
  écrite qu'après coup (ADR 0001) ; ce qui existait avant : à confirmer.
- Une borne à la taille de la base.

## Action

- SQLite sauvegardé par le `sqlite3 ".backup"` de l'hôte, jamais par
  `sqlite_databases` de borgmatic (PR #715, ADR 0001 ; règle reprise dans
  `AGENTS.md`).
- Rétention des journaux ramenée à 30 jours (requêtes, connexions) et 90 jours
  (accès, actions), ADR 0005.
- À confirmer : le `VACUUM` de la base, dont l'ADR 0005 ne trouve aucune trace.

Sources : ADR 0001 et 0005 ;
[reconstruction-pangolin.md](../runbooks/reconstruction-pangolin.md) (taille
de l'archive).
