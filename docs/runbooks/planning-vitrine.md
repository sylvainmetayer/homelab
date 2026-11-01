# planning.sylvain.dev (Cloudflare Pages) : déploiement en échec, domaine en attente, jeton du beacon, dérive du plan

Vitrine statique de planning-equipes : dossier `site/` du dépôt
`sylvainmetayer/planning-equipes`, sans build, publié par le projet Cloudflare
Pages `planning-equipes`. Infra dans `tofu/planning` (état
`homelab/planning.tfstate`). Détail :
[README du module](../../tofu/planning/README.md).

## Symptôme

- Moniteur « Planning (vitrine) » DOWN (groupe Cloudflare,
  `tofu/pangolin_config/external_monitors.tf`).
- Un merge sur `main` qui touche `site/**` n'est pas en ligne.
- Le domaine personnalisé reste « en attente » dans le dashboard Pages,
  ou erreur de certificat sur `https://planning.sylvain.dev`.
- `mise run plan-planning` montre un échec du `check "beacon_token"`, ou
  des changements.

## Diagnostic

Depuis le dépôt homelab (mise charge `CLOUDFLARE_API_TOKEN` et
`CLOUDFLARE_ACCOUNT_ID`) :

```bash
curl -sI https://planning.sylvain.dev | head -1
dig +short CNAME planning.sylvain.dev        # planning-equipes(-xxx).pages.dev.

# Derniers déploiements : branche, étape, état
mise exec -- sh -c 'curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/planning-equipes/deployments" \
  | jq ".result[:5][] | {created_on, environment, branch: .deployment_trigger.metadata.branch, stage: .latest_stage}"'

# Domaine personnalisé : état et validation
mise exec -- sh -c 'curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/planning-equipes/domains/planning.sylvain.dev" \
  | jq ".result | {status, validation_data, verification_data}"'
```

- **Pas de déploiement après un merge** : le projet ne builde que les
  commits qui touchent `site/**` (`path_includes`). Un merge hors de ce
  dossier ne déclenche rien, normal. Sinon : l'app GitHub « Cloudflare
  Workers and Pages » a-t-elle toujours accès au dépôt (GitHub → Settings
  → Applications → Configure) ?
- **Déploiement en échec** : son journal dans le dashboard (Workers & Pages
  → `planning-equipes` → le déploiement). Cause habituelle : `site/wrangler.toml`
  du dépôt (dossier publié, date de compatibilité), qui fait foi.
- **Domaine en attente** : le CNAME doit viser le sous-domaine `pages.dev`
  du projet (`mise exec -- tofu -chdir=tofu/planning output -raw
  pages_subdomain`). Sans lui, `planning.sylvain.dev` tombe sur le joker
  `*.sylvain.dev` vers Pangolin et la validation échoue.
- **Plan qui dérive** :
  - `check "beacon_token"` en échec : le jeton du beacon n'est pas (ou plus)
    dans `site/index.html` **et** `site/en/index.html` sur `main`. Arrive
    au premier apply, et quand le site Web Analytics est recréé (nouveau
    jeton).
  - `deployment_configs` est ignoré exprès (`wrangler.toml` fait foi) : une
    différence ailleurs sur le projet est une modification faite dans le
    dashboard.

  Le plan lit les deux pages sur GitHub : `export GITHUB_TOKEN="$(gh auth
  token)"` avant.

## Réparation

- **Relancer un déploiement de production** :

  ```bash
  mise exec -- sh -c 'curl -sS -X POST -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -F branch=main \
    "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/planning-equipes/deployments" | jq .success'
  ```

  Ou « Retry deployment » dans le dashboard. Un retour arrière : « Rollback »
  sur un déploiement réussi précédent, puis corriger `site/` par une PR
  dans `planning-equipes`.
- **App GitHub sans accès** : l'ajouter au dépôt sur sa page de
  configuration, ou laisser Tofu le faire (`TF_VAR_cloudflare_github_installation_id`
  et un PAT classique scope `repo`, README du module).
- **Domaine en attente, CNAME absent ou faux** : `mise run plan-planning`
  puis `mise run apply-planning` (Sylvain) remet
  `ovh_domain_zone_record.planning`. Si le domaine reste en attente une
  fois le CNAME en place, relancer sa validation depuis l'onglet Custom
  domains du projet.
- **Jeton du beacon** :

  ```bash
  mise exec -- tofu -chdir=tofu/planning output -raw web_analytics_token
  ```

  Le recopier dans la paire `"token": "<jeton>"` du `data-cf-beacon` de
  `site/index.html` et `site/en/index.html`, par une PR dans
  `planning-equipes` ; son merge redéploie (chemin `site/**`).
- **Modification faite dans le dashboard** : `mise run apply-planning`
  ramène le projet au code, ou reporter le réglage dans
  `tofu/planning/cloudflare.tf` par une PR.

## Vérification

```bash
curl -sI https://planning.sylvain.dev | head -1       # 200
curl -sI https://planning.sylvain.dev/en/ | head -1   # 200
mise run plan-planning                                 # aucun changement, sans avertissement beacon_token
```

Les en-têtes de `site/_headers` (CSP, HSTS) dans le `curl -sI`. Moniteur
« Planning (vitrine) » UP.

## Prévention

- Toute modification du projet Pages passe par `tofu/planning`, jamais par
  le dashboard.
- Recréer le site Web Analytics (changement d'hôte) oblige à recopier le
  jeton : le `check` du plan le rappelle.
