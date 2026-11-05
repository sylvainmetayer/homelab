# Pangolin : cibles sans schéma de sonde, 503

## Symptôme

Gramps et scanopy répondaient **503** (« no available server » de Traefik),
puis les trois cibles de Flip Planning ont fini à `hcHealth="unhealthy"` de la
même façon (`websites.tf`). Durée : le dépôt dit deux choses, « pendant des
heures » (`notifications.tf`) et « pendant des semaines » (`resource_defaults.tf`).
Laquelle est juste : à confirmer. Date : corrigé le 30/08/2026 (commits `8a9aaded`, `08c63c6f`) ; début de la
panne : à confirmer.

## Cause

`hc_scheme`, `hc_mode` et `hc_port` de `pangolin_target` sont
`optional+computed` et non déclarés : Pangolin les enregistre **NULL** quand
Tofu ne les envoie pas, il ne met pas de valeur par défaut (`websites.tf`).
Une sonde sans schéma ne réussit jamais ; Pangolin retire alors la cible du
répartiteur de charge. Pourquoi seules certaines cibles ont été touchées :
à confirmer.

## Ce qui a manqué

- Un plan muet : « No changes » quelles que soient les valeurs vivantes.
- **Aucune alerte** : Uptime Kuma surveillait les applis sans prévenir
  personne ; la panne a été trouvée en lisant l'API de Pangolin à la main
  (`notifications.tf`).

## Action

- Les `hc_*` sont écrits en dur dans `pangolin_target` (`websites.tf`), pour que
  le plan compare à une valeur connue.
- Un audit au plan, `terraform_data.target_probe_config` (`rules.tf`), **échoue**
  sur une sonde activée sans schéma ou sans port.
- Alertes sur Telegram et ntfy pour chaque moniteur (`notifications.tf`) ;
  Telegram ne passe pas par Pangolin, donc une panne de Pangolin arrive aussi.
- Page de maintenance automatique de Pangolin quand toutes les cibles d'une
  ressource sont hors service (`maintenance.tf`), à la place du message brut.

Sources : `AGENTS.md` ; `tofu/pangolin_config/websites.tf`,
`notifications.tf`, `resource_defaults.tf`, `rules.tf`, `maintenance.tf`.
