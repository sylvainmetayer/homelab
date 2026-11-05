# Pangolin : les cibles de Flip Planning détruites

## Symptôme

Les **cibles** (targets) de la ressource Flip Planning ont été **détruites**
(`AGENTS.md`, règle « Pangolin provider » : « two outages: flip-planning's
targets destroyed… »). Ce qui les a détruites, la date, la durée de la
coupure, les ressources touchées au-delà de Flip Planning : à confirmer, le
dépôt ne les donne pas.

## Cause

À confirmer : le dépôt ne décrit pas le mécanisme. Il établit seulement la
classe de panne, que `AGENTS.md` range avec l'autre : des attributs
`optional+computed` non déclarés veulent dire « accepter ce que l'API
contient », ils apparaissent « (known after apply) » à chaque mise à jour, et
un plan ne peut jamais contredire le serveur (`resource_defaults.tf`). Les cinq
attributs de `pangolin_resource` épinglés depuis : `ssl`, `enabled`,
`block_access`, `email_whitelist_enabled`, `sticky_session`. Que l'un d'eux ait
détruit les cibles n'est pas écrit.

## Ce qui a manqué

- Un plan qui dit « No changes » **quelle que soit la valeur réelle** : rien
  ne signalait la dérive tant que rien ne mettait ces ressources à jour
  (`resource_defaults.tf`).
- Une règle écrite : `AGENTS.md` la donne comme tirée de deux pannes (celle-ci
  et [la suivante](pangolin-cibles-sans-sonde-503.md)) ; quand elle a été
  écrite : à confirmer.

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
