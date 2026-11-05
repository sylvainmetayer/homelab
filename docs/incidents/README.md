# Incidents

Une page par panne **réellement arrivée** et dont le dépôt garde la trace.
Les runbooks ([../runbooks/](../runbooks/README.md)) disent quoi faire quand
cela arrive ; les ADR ([../adr/](../adr/README.md)) disent pourquoi un choix a
été fait ; ici on garde ce qui s'est passé, pour ne pas le refaire.

Règle d'écriture : rien d'inventé. Une date, une durée ou une cause que le
dépôt ne donne pas s'écrit « à confirmer », avec la source de ce qui est dit.
Pas de personne nommée : « le foyer » pour les utilisateurs, Sylvain pour
celui qui répare.

## Modèle

Fichier `sujet-court.md`, une page d'écran, quatre rubriques puis les sources :

```markdown
# Titre : ce qui est tombé

## Symptôme
Ce qu'on a vu, quand, combien de temps (« à confirmer » sinon).
## Cause
Ce que le dépôt établit ; le reste « à confirmer ».
## Ce qui a manqué
Le contrôle, l'alerte ou la règle dont l'absence a laissé durer ou passer.
## Action
Ce qui a été fait (avec la PR, le fichier) et ce qui reste à faire.

Sources : fichiers et PR du dépôt.
```

Ajouter la page à `nav:` de `mkdocs.yml` (le build échoue sinon) et au tableau
ci-dessous.

## Pannes documentées

| Date | Panne | Page |
|---|---|---|
| à confirmer | Pangolin : cibles de Flip Planning détruites par une mise à jour sans attributs épinglés | [pangolin-cibles-detruites.md](pangolin-cibles-detruites.md) |
| corrigé le 30/08/2026 | Pangolin : cibles sans schéma de sonde, 503 sur gramps, scanopy et Flip Planning | [pangolin-cibles-sans-sonde-503.md](pangolin-cibles-sans-sonde-503.md) |
| 30/09 au 27/10/2026 | vzdump de la VM docker en échec chaque soir (disque plein) | [vzdump-disque-plein.md](vzdump-disque-plein.md) |
| 07/10/2026 | Pangolin figé pendant sa sauvegarde (verrou SQLite) | [pangolin-verrou-sqlite.md](pangolin-verrou-sqlite.md) |
| 29/10/2026 | Notifications ntfy coupées sur Android après le retrait d'un topic | [ntfy-topic-retire.md](ntfy-topic-retire.md) |

## Mentionnés, pas assez sourcés pour une page

- **Nextcloud, dump de sauvegarde en échec en octobre 2026** : une seule ligne
  de la [matrice des données](../matrice-des-donnees.md) (« Jours sans nuit
  réussie »). Ni la cause, ni la durée, ni la correction n'y sont. À
  documenter si Sylvain en retrouve la trace.
- **Widget Beszel de Homepage, coupure du 29/10/2026** : cause décrite dans
  [architecture.md](../architecture.md) (403 de PocketBase pour un superuser
  venu d'une autre adresse, réseau `beszel_homepage` créé depuis) ; heure de
  début et de fin non trouvées.
