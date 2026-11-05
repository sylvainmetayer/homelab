# Pangolin : les cibles de Flip Planning détruites

## Symptôme

Une mise à jour de `tofu/pangolin_config` a **détruit les cibles** (targets)
de la ressource Flip Planning (`AGENTS.md`, règle « Pangolin provider »). Date,
durée de la coupure, ressources touchées au-delà de Flip Planning : à
confirmer, le dépôt ne les donne pas.

## Cause

Des attributs `optional+computed` de `pangolin_resource` laissés sans valeur.
Non déclarés, ils veulent dire « accepter ce que l'API contient » : ils
apparaissent « (known after apply) » à chaque mise à jour, et un plan ne peut
jamais contredire le serveur (`resource_defaults.tf`). Les cinq épinglés depuis :
`ssl`, `enabled`, `block_access`, `email_whitelist_enabled`, `sticky_session`.
Le chemin exact qui a détruit les cibles : à confirmer.

## Ce qui a manqué

- Un plan qui dit « No changes » **quelle que soit la valeur réelle** : rien
  ne signalait la dérive tant que rien ne mettait ces ressources à jour
  (`resource_defaults.tf`).
- Une règle écrite : elle n'est entrée dans `AGENTS.md` qu'après deux pannes
  (celle-ci et [la suivante](pangolin-cibles-sans-sonde-503.md)).

## Action

- Toute valeur `optional+computed` est déclarée (règle d'`AGENTS.md`).
  `pangolin_resource` lit ses valeurs dans `local.resource_pins`
  (`resource_defaults.tf`, valeurs relevées par l'API le 2026-08-31, identiques
  sur les seize ressources gérées).
- Ce qui reste non épinglé (`tls_server_name`, `maintenance_estimated_time`) a
  sa raison écrite à côté : un null ne s'épingle pas.
- Détail et exceptions : [tofu/pangolin_config/README.md](../../tofu/pangolin_config/README.md).

Sources : `AGENTS.md` ; `tofu/pangolin_config/resource_defaults.tf` ;
`tofu/pangolin_config/maintenance.tf` (« cost two outages »).
