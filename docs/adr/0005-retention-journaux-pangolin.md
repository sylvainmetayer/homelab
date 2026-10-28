# 0005. Base de Pangolin : rétention des journaux bornée

- **Statut** : acceptée (rétention) ; VACUUM à confirmer
- **Date** : 2026-10-28

## Contexte

Pangolin garde ses journaux (requêtes, connexions, accès, actions) dans sa
base SQLite `db.sqlite`, sauvegardée chaque nuit. La rétention de l'org
valait 9001 jours, donc sans fin : la base ne faisait que grossir. Une base
plus grosse rallonge la copie de sauvegarde ; le 07/10/2026, une sauvegarde
avait déjà figé Pangolin sur un verrou SQLite
([0001](0001-sauvegardes-borgmatic.md)).

## Décision

- Rétention des journaux de l'org réglée par l'API de Pangolin : requêtes et
  connexions **30 jours**, accès et actions **90 jours**.
- Un `VACUUM` de `db.sqlite` pour rendre la place déjà prise : **à
  confirmer**, aucune trace dans le dépôt ni dans les PR.

## Alternatives écartées

- **Garder la rétention par défaut** : croissance sans borne de la base et
  de chaque archive.

## Conséquences

- Les journaux d'accès au-delà de 90 jours sont perdus (les archives Borg en
  gardent l'historique selon leur propre rétention).
- Réglage hors code : un Pangolin reconstruit depuis Borg le retrouve dans
  sa base, un Pangolin neuf non. À reporter à la main dans ce cas.

## Liens

PR #915 (section « hors code ») ; PR #715 (incident du verrou SQLite) ;
[runbooks/reconstruction-pangolin.md](../runbooks/reconstruction-pangolin.md).
