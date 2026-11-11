# 0006. Objets faits main : audités au plan dans Pangolin, relevés dans Uptime Kuma

- **Statut** : acceptée ; passerelles VPN déclarées en Tofu grâce au fork de [0021](0021-provider-pangolin-du-fork.md), audit `vpn_gateways` retiré (PR #1126)
- **Date** : 2026-08-30 (couverture pays), 2026-08-31 (règles), 2026-10-06 (VPN), 2026-10-28 (cibles, jetons, rôles), 2026-11-11 (liaisons, authentification, ressources privées)

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

Le 11/11 (audit ex3), `access_inventory` lit aussi `binding_inventory.tf` : les
rôles et utilisateurs liés à chaque ressource publique, les mots de passe, PIN
et header auth posés dessus (déjà dans la liste des ressources, sans appel en
plus), les ressources privées et leurs rôles, utilisateurs et clients OLM.
Tout ce que la configuration ne déclare pas fait échouer le plan. Coût : 1
appel pour la liste des ressources privées, 2 par ressource publique (rôles,
utilisateurs), 3 par ressource privée (rôles, utilisateurs, clients) : une
centaine d'appels de plus, de même nature que ceux des cibles et des règles.

**Limites connues** : pas de point d'accès pour les lire en une fois, d'où un
appel par ressource ; les ressources publiques sont comparées par nom (un
doublon fait main du nom d'une ressource gérée hérite de ses liaisons : la
couverture de `rules.tf` est ce qui le voit) ; les clés d'API de Pangolin (que
le provider ne déclare qu'en partie) et les clients OLM eux-mêmes (hors liaison
à une ressource) ne sont pas audités ; le contenu d'un mot de passe, d'un PIN
ou d'un header auth ne se lit pas (seule son existence se voit : un PIN changé à
la main passe).

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
