# 0002. Pangolin, seule entrée publique ; FR/DE seulement ; chemins ouverts relus

- **Statut** : acceptée
- **Date** : 2026-01 (reprise du dépôt), 2026-08-30 (pays), 2026-10-16 (relecture)

## Contexte

Les applis tournent à la maison et sur flip, sans IP publique ni port
entrant. Il faut une porte unique, avec SSO, et des règles écrites dans le
code plutôt que cliquées.

## Décision

- **Pangolin** (VM Hetzner) est la seule entrée publique ; chaque hôte a un
  **Newt**, tunnel WireGuard sortant. Tout est déclaré dans
  `tofu/pangolin_config`, jamais en labels Docker.
- **FR et DE seulement** (`local.allowed_countries`) sur toute ressource
  publique, plus un pays de voyage à date de fin (`travel_countries`).
- **Chemins ouverts sans SSO** (priorités 2 à 9, gardés par le secret de
  l'appli), relus sur la version d'image de `path_bypass_images.json` : à
  chaque montée, `path-bypass-review.yaml` attend une approbation humaine
  (environnement `relecture-chemins-publics`). Priorité 1 : DROP d'antislash.

## Alternatives écartées

- **Ports ouverts à la maison** : expose le LAN.
- **Labels Docker `pangolin.public-resources.*`** : hors de Tofu, ni testés.
- **Version épinglée à la main dans le test Tofu** : un commit manuel par PR
  Renovate (remplacé par #746).

## Conséquences

- Une panne de Pangolin coupe toutes les applis.
- Une ressource faite dans l'UI fait échouer le plan ([0006](0006-objets-faits-main-audites.md)).
- Depuis l'étranger, il faut déclarer le voyage puis appliquer.

## Liens

PR #520, #746 ; [architecture.md](../architecture.md), [acces-mobile.md](../acces-mobile.md),
[runbooks/pangolin-injoignable.md](../runbooks/pangolin-injoignable.md).
