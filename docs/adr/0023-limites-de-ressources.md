# 0023. Limites : mémoire mesurée sur chaque service, pas de quota CPU hors traitements par lots

- **Statut** : acceptée
- **Date** : 2026-09-05 (doctrine), 2026-10-29 (recalage), 2026-10-31 (Immich, Pangolin)

## Contexte

La VM docker a 3 cœurs et 12 Gio. Des plafonds `cpus:` de 0,25 à 1,50 et `mem_limit`
ont été posés le 2026-08-29 (`7db528a6`, sans message d'explication). Une semaine
plus tard : 24,5 vCPU et 23 Gio déclarés pour 3,5 % de CPU et 5 Gio de RSS mesurés.
Ce qui gênait : gramps en boucle d'OOM, `dawarich-db` et `rss` à leur plafond,
cache évincé, disque sollicité ; services monothread freinés (`4cef7c44`).

## Décision

- **`mem_limit` sur chaque service** (hors worker `compose/immich`, lancé sur un poste), à environ 2× le pic (`memory.peak`).
- **`mem_reservation`** environ égale au pic sur les bases et ce qui touche son plafond.
- **Pas de `cpus:`**, sauf les traitements par lots (OCR, conversion, workers, crawl, sauvegarde, transferts) :
  `cpus: 2.00` + `cpu_shares: 512` ; chacun laisse un cœur au reste et cède sous contention.
- Vérifier le nombre de workers par défaut d'une image contre son plafond.

## Alternatives écartées

- **Quotas CPU partout** (en place du 2026-08-29 au 2026-09-05) : un quota sous
  un cœur freine un pic monothread même sur un hôte au repos.
- **Plafonds serrés** : un conteneur à son plafond n'est pas toujours tué (gramps
  l'était) : il perd son cache et sollicite le disque, le goulot de cette VM.
- **Aucune limite** (avant `65c73419`, 2026-08-03, dawarich seul ; ailleurs jusqu'au
  2026-08-29) : raison non écrite, à confirmer.

## Conséquences

- Les plafonds suivent les mesures : recalage #991, limites manquantes d'Immich et
  de Pangolin posées par #1038 ; relevé hebdomadaire par `mem_report`.
- Une limite peut manquer sans que Compose le voie : conteneurs du Pi créés
  avant l'activation du contrôleur mémoire, recréés le 2026-11-03 (QG homelab).

## Liens

Commit `4cef7c44` ; [resource-limits.md](../conventions/resource-limits.md), `ansible/roles/mem_report/README.md`.
