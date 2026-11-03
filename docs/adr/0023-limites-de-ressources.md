# 0023. Limites : mémoire mesurée sur chaque service, pas de quota CPU hors traitements par lots

- **Statut** : acceptée
- **Date** : 2026-09-05 (doctrine), 2026-10-29 et 2026-10-31 (recalages)

## Contexte

La VM docker a 3 cœurs et 12 Gio. Des plafonds `cpus:` 0,25 à 0,50 et `mem_limit`
ont été posés le 2026-08-29 (`7db528a6`, sans message d'explication). Une semaine
plus tard : 24,5 vCPU et 23 Gio déclarés pour 3,5 % de CPU et 5 Gio de RSS mesurés.
Ce qui gênait : gramps en boucle d'OOM, `dawarich-db` et `rss` à leur plafond,
cache évincé, disque sollicité ; services monothread freinés (`4cef7c44`).

## Décision

- **`mem_limit` sur chaque service**, à environ 2× le pic mesuré (`memory.peak`).
- **`mem_reservation`** environ égale au pic sur les bases et ce qui touche son plafond.
- **Pas de `cpus:`**, sauf les traitements par lots (OCR, conversion, workers) :
  `cpus: 2.00` + `cpu_shares: 512`, qui laissent toujours un cœur au reste.
- Vérifier le nombre de workers par défaut d'une image contre son plafond.

## Alternatives écartées

- **Quotas CPU partout** (en place du 2026-08-29 au 2026-09-05) : un quota sous
  un cœur freine un pic monothread même sur un hôte au repos.
- **Plafonds serrés** : un conteneur à son plafond n'est pas tué, il perd son
  cache et sollicite le disque, le goulot de cette VM.
- **Aucune limite** (avant `65c73419`, 2026-08-03) : raison non écrite, à confirmer.

## Conséquences

- Les plafonds suivent les mesures : recalages #991 et #1038 ; relevé hebdomadaire
  par `mem_report`.
- Une limite peut manquer sans que Compose le voie : conteneurs du Pi créés
  avant l'activation du contrôleur mémoire, recréés le 2026-11-03 (QG homelab).

## Liens

Commit `4cef7c44` ; [resource-limits.md](../conventions/resource-limits.md), `ansible/roles/mem_report/README.md`.
