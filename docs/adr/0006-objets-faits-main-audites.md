# 0006. Objets faits main : audités au plan dans Pangolin, relevés dans Uptime Kuma

- **Statut** : acceptée
- **Date** : 2026-08-30 (couverture pays), 2026-08-31 (règles), 2026-10-06 (VPN), 2026-10-28 (cibles, jetons, rôles)

## Contexte

Une partie de Pangolin et d'Uptime Kuma se fait encore dans l'UI : ce que le
provider ne sait pas déclarer (passerelles VPN en mode `gateway`), ou un
objet créé à la main puis oublié. Une règle, une cible ou un jeton d'accès
oublié peut ouvrir une appli sans que le plan le dise.

## Décision

Dans Pangolin, des `terraform_data` dont les `precondition` lisent l'API
font échouer le plan sur tout objet inconnu : `rule_inventory` et
`geo_rule_coverage` (règles, couverture pays), `target_inventory` (cibles),
`access_inventory` (jetons d'accès, rôles), `vpn_gateways` (les deux sorties
VPN faites dans l'UI, leur mode et leur site). Une exception se déclare par
id avec sa raison ; une liste tronquée par l'API est refusée. Dans Uptime
Kuma, ce qui reste fait main est seulement relevé (`status_page_site.tf`).

## Alternatives écartées

- **Tout importer en Tofu** : impossible pour les passerelles VPN (provider
  1.6.1 : `host`/`cidr`/`http` seulement) et les clés d'API d'Uptime Kuma.
- **Audit ponctuel à la main** : celui du 31/08 a laissé des restes (#525).

## Conséquences

- Un objet créé dans l'UI bloque le prochain apply : le supprimer ou le
  déclarer d'abord (trois objets obsolètes supprimés par #915).
- Le plan dépend de l'API de Pangolin (lecture), tests en `override_data`.

## Liens

PR #520 (couverture pays), #912, #915 ; commits `0b7560e3` (`rule_inventory`)
et `b473f1f8` (`vpn_gateways`) ; issue #525.
