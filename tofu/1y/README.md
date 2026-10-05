# tofu/1y

Infra du gestionnaire d'URL courtes [r.sylvain.dev](https://r.sylvain.dev) (code : dépôt [`sylvainmetayer/1y`](https://github.com/sylvainmetayer/1y), 11ty), migré de Netlify vers Cloudflare Pages sur le modèle de [`tofu/ref`](../ref/README.md).

| Ressource | Rôle |
|---|---|
| `github_repository.r` | Dépôt `1y`, **importé** (bloc `import` de `github.tf`) : description, sujets, options de fusion, scan de secrets |
| `github_repository_vulnerability_alerts.r` / `github_repository_dependabot_security_updates.r` | Alertes Dependabot oui, PR Dependabot non : Renovate (`renovate.json` du dépôt) gère les montées |
| `github_workflow_repository_permissions.r` | `GITHUB_TOKEN` en lecture seule par défaut |
| `github_branch_protection.r_master` | Pas de suppression ni de force-push sur `master` (sans PR obligatoire) |
| `github_app_installation_repository.cloudflare` / `.renovate` | Accès des apps GitHub Cloudflare et Renovate au dépôt (si `*_github_installation_id` est renseigné) |
| `cloudflare_pages_project.r` | Build `npm run build` → `_site`, déploiement à chaque push sur `master`, previews sur les autres branches |
| `data.github_repository_file.mise` | `mise.toml` du dépôt : une précondition de `cloudflare_pages_project.r` vérifie que `var.node_version` (variable `NODE_VERSION` du build Pages) correspond à sa version de Node |
| `cloudflare_pages_domain.r` | Domaine personnalisé `r.sylvain.dev` |
| `ovh_domain_zone_record.r` | CNAME `r` → `<projet>.pages.dev` (prime sur le joker `*.sylvain.dev` de `tofu/dns`) |

**Version de Node** : Pages ne lit pas `mise.toml` (seulement `.nvmrc`/`.node-version`), d'où `NODE_VERSION`. Pour monter de version : merger d'abord la PR du dépôt `1y` qui change `mise.toml`, puis passer `var.node_version` à la même valeur. Tant que les deux divergent, `plan` et `apply` échouent sur la précondition.

⚠️ Au premier apply (provider cloudflare 5.27.0), l'API a enregistré `NODE_VERSION` **vide** en production (la preview avait bien la valeur), alors que le state indiquait la bonne : le `plan` suivant n'était pas vide. Après un changement de version, relancer `plan` ; s'il montre encore `NODE_VERSION`, corriger la production directement :

```bash
mise exec -- bash -c 'curl -s -X PATCH -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" \
  -d "{\"deployment_configs\":{\"production\":{\"env_vars\":{\"NODE_VERSION\":{\"type\":\"plain_text\",\"value\":\"26\"}}}}}" \
  "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/1y"'
```

Pas de Web Analytics : les redirections de `_redirects` sont servies en bordure, aucune page ne chargerait le beacon.

## Prérequis

Les mêmes que [`tofu/ref`](../ref/README.md#prérequis) : `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID` dans `secrets.sops.yaml`, et l'app GitHub « Cloudflare Workers and Pages » installée sur le compte. En mode « Only select repositories » :

```bash
export TF_VAR_cloudflare_github_installation_id=<id>   # même ID que pour tofu/ref
export TF_VAR_renovate_github_installation_id=<id>     # idem pour l'app Renovate, si en mode sélectif
export GITHUB_TOKEN=<PAT classique, scope repo>
```

## Utilisation

```bash
export GITHUB_TOKEN="$(gh auth token)"
mise exec -- tofu -chdir=tofu/1y init
mise exec -- tofu -chdir=tofu/1y plan
```

## Migration depuis Netlify

1. Merger la PR du dépôt `1y` (11ty 3, `wrangler.toml`, `_redirects` au format Cloudflare).
2. **Importer l'enregistrement DNS existant** de `r.sylvain.dev` (créé à la main, il pointe vers Netlify) : sinon OVH en crée un second à côté. Son ID :

   ```bash
   # API OVH : GET /domain/zone/sylvain.dev/record?subDomain=r
   mise exec -- tofu -chdir=tofu/1y import ovh_domain_zone_record.r sylvain.dev.<id>
   ```

   S'il n'existe pas d'enregistrement `r` (domaine délégué autrement, redirection OVH…), sauter cette étape.
3. `tofu apply` : crée le projet Pages, le domaine personnalisé et bascule le CNAME vers `<projet>.pages.dev`. Le nom `1y.pages.dev` est probablement déjà pris : Cloudflare attribue alors `1y-xxx.pages.dev`, repris automatiquement par le CNAME (sortie `pages_subdomain`).
4. **Lancer le premier déploiement** : Pages ne builde qu'au push suivant sa création, et le CNAME bascule dès l'apply — tant qu'il n'y a pas de déploiement, `r.sylvain.dev` répond 522. Depuis le dashboard, ou :

   ```bash
   curl -X POST -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -F branch=master \
     "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/1y/deployments"
   ```
5. Vérifier `curl -sI https://r.sylvain.dev/signal` (301), puis supprimer le site et le domaine `r.sylvain.dev` côté Netlify.
