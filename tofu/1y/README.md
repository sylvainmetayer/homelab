# tofu/1y

Infra du gestionnaire d'URL courtes [r.sylvain.dev](https://r.sylvain.dev) (code : dépôt [`sylvainmetayer/1y`](https://github.com/sylvainmetayer/1y), 11ty), migré de Netlify vers Cloudflare Pages sur le modèle de [`tofu/ref`](../ref/README.md).

Le dépôt, le projet Pages, son domaine et le CNAME viennent du module commun [`tofu/modules/pages_site`](../modules/pages_site), appelé dans `main.tf` (`module.pages`), comme pour `tofu/ref` et `tofu/site`.

| Ressource | Rôle |
|---|---|
| `module.pages.github_repository.this` | Dépôt `1y`, **importé** en 2026 (le bloc `import` est retiré depuis) : description, sujets, options de fusion, scan de secrets |
| `module.pages.github_repository_vulnerability_alerts.this` / `module.pages.github_repository_dependabot_security_updates.this` | Alertes Dependabot oui, PR Dependabot non : Renovate (`renovate.json` du dépôt) gère les montées |
| `module.pages.github_workflow_repository_permissions.this[0]` | `GITHUB_TOKEN` en lecture seule par défaut |
| `module.pages.github_branch_protection.production[0]` | Pas de suppression ni de force-push sur `master` (sans PR obligatoire) |
| `module.pages.github_app_installation_repository.cloudflare` / `github_app_installation_repository.renovate` | Accès des apps GitHub Cloudflare et Renovate au dépôt (si `*_github_installation_id` est renseigné) |
| `module.pages.cloudflare_pages_project.wrangler[0]` | Build `npm run build` → `_site`, déploiement à chaque push sur `master`, previews sur les autres branches |
| `data.github_repository_file.mise` / `.wrangler` | `mise.toml` et `wrangler.toml` du dépôt : une postcondition (`node.tf`) vérifie qu'ils déclarent la même version de Node |
| `module.pages.cloudflare_pages_domain.this` | Domaine personnalisé `r.sylvain.dev` |
| `module.pages.ovh_domain_zone_record.cname` | CNAME `r` → `<projet>.pages.dev` (prime sur le joker `*.sylvain.dev` de `tofu/dns`) |

**Version de Node** : avec un `wrangler.toml`, le build Pages ignore les variables du dashboard (log : `Build environment variables: (none found)`) et ne lit pas `mise.toml`. La version vient donc de `[vars] NODE_VERSION` dans `wrangler.toml`, gérée côté dépôt `1y` (Renovate met à jour les deux fichiers ensemble, un workflow vérifie qu'ils sont égaux). Ici, la postcondition fait échouer `plan` et `apply` si les deux divergent sur la branche de production.

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
   mise exec -- tofu -chdir=tofu/1y import module.pages.ovh_domain_zone_record.cname sylvain.dev.<id>
   ```

   S'il n'existe pas d'enregistrement `r` (domaine délégué autrement, redirection OVH…), sauter cette étape.
3. `tofu apply` : crée le projet Pages, le domaine personnalisé et bascule le CNAME vers `<projet>.pages.dev`. Le nom `1y.pages.dev` est probablement déjà pris : Cloudflare attribue alors `1y-xxx.pages.dev`, repris automatiquement par le CNAME (sortie `pages_subdomain`).
4. **Lancer le premier déploiement** : Pages ne builde qu'au push suivant sa création, et le CNAME bascule dès l'apply — tant qu'il n'y a pas de déploiement, `r.sylvain.dev` répond 522. Depuis le dashboard, ou :

   ```bash
   curl -X POST -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -F branch=master \
     "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/1y/deployments"
   ```
5. Vérifier `curl -sI https://r.sylvain.dev/signal` (301), puis supprimer le site et le domaine `r.sylvain.dev` côté Netlify.
