# tofu/planning

Infra de la vitrine de planning-equipes, [planning.sylvain.dev](https://planning.sylvain.dev) : le dossier `site/` du dépôt [`sylvainmetayer/planning-equipes`](https://github.com/sylvainmetayer/planning-equipes), page statique sans build, servie par Cloudflare Pages sur le modèle de [`tofu/ref`](../ref/README.md).

| Ressource | Rôle |
|---|---|
| `github_app_installation_repository.cloudflare` | Accès de l'app GitHub Cloudflare au dépôt (si `cloudflare_github_installation_id` est renseigné) |
| `cloudflare_pages_project.planning` | Projet `planning-equipes` : dossier racine `site`, aucune commande de build, sortie `.` ; production à chaque merge sur `main`, aperçu sur chaque branche, le tout limité aux commits qui touchent `site/**` |
| `cloudflare_pages_domain.planning` | Domaine personnalisé `planning.sylvain.dev` |
| `ovh_domain_zone_record.planning` | CNAME `planning` → `<projet>.pages.dev` (prime sur le joker `*.sylvain.dev` de `tofu/dns`) |
| `cloudflare_web_analytics_site.planning` | Pages vues, sans injection automatique ; jeton du beacon en sortie `web_analytics_token`, comparé au plan aux deux pages du dépôt (`check "beacon_token"`) |

**Le dépôt n'est pas ici** : `planning-equipes` est géré par `tofu/github` (`repository_planning_equipes.tf` : visibilité, protection de `main`, scan de secrets…), qui ne déclare aucun réglage GitHub Pages : rien à y désactiver (GitHub Pages n'est pas activé sur le dépôt, API relue le 2026-11-01, et la PR de la vitrine retire son workflow). Un module à part, avec son propre état (`homelab/planning.tfstate`), comme `ref`, `site` et `1y` : un site Pages = un module, et `tofu/github`, dont l'état est chiffré et qui pilote les dépôts et environnements de déploiement du homelab, n'a pas à porter de jeton Cloudflare ni de zone OVH.

`site/wrangler.toml` du dépôt fait foi pour le dossier publié (`pages_build_output_dir = "."`) et la date de compatibilité : d'où `ignore_changes = [deployment_configs]`, comme dans `tofu/ref`. Les en-têtes (CSP, HSTS…) sont dans `site/_headers`.

## Prérequis

Les mêmes que [`tofu/ref`](../ref/README.md#prérequis), déjà en place : `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID` dans `secrets/secrets.sops.yaml` (le jeton a déjà Pages Edit et Web Analytics Edit), et l'app GitHub « Cloudflare Workers and Pages » installée sur le compte. Selon son mode (*Settings → Applications → Cloudflare Workers and Pages → Configure* sur GitHub) :

- **« All repositories »** : rien à faire ;
- **« Only select repositories »** : soit ajouter `planning-equipes` à la main sur cette page, soit laisser Tofu le faire :

  ```bash
  export TF_VAR_cloudflare_github_installation_id=<id>   # même ID que pour tofu/ref, visible dans l'URL de la page
  export GITHUB_TOKEN=<PAT classique, scope repo>         # PUT /user/installations/… refuse le jeton de gh auth token
  ```

## Utilisation

```bash
export GITHUB_TOKEN="$(gh auth token)"   # lecture des deux pages pour le check beacon_token
mise run plan-planning    # init puis plan
mise run apply-planning
```

mise charge `secrets/secrets.sops.yaml` dans l'environnement (identifiants S3 du backend, OVH) ; `CLOUDFLARE_API_TOKEN` et `CLOUDFLARE_ACCOUNT_ID` sont lus par le provider `sops` (`secrets.tf`). Les tests : `tofu -chdir=tofu/planning init -backend=false && tofu -chdir=tofu/planning test` (ou `mise run tofu-test`).

## Ordre des opérations (premier apply)

1. **La PR de la vitrine est mergée** dans `planning-equipes` : `site/` est sur `main`, avec `wrangler.toml`, `_headers` et le jeton factice `A_REMPLACER_PAR_LE_JETON` dans les deux pages. Sans elle, le projet n'aurait rien à publier.
2. **App GitHub Cloudflare** : vérifier qu'elle a accès au dépôt (voir « Prérequis »).
3. `mise run plan-planning` : 4 ressources à créer (5 avec `TF_VAR_cloudflare_github_installation_id`), rien à modifier ni détruire, et l'avertissement « Check block assertion known after apply » sur `beacon_token` (le jeton n'existe pas encore). Les plans suivants l'affichent en échec tant que le jeton n'est pas recopié (étape 5) : attendu. Puis `mise run apply-planning`. Le nom `planning-equipes.pages.dev` peut être déjà pris : Cloudflare attribue alors `planning-equipes-xxx.pages.dev`, repris automatiquement par le CNAME (sortie `pages_subdomain`).
4. **Lancer le premier déploiement** : Pages ne builde qu'au push suivant sa création, et le CNAME bascule dès l'apply (`planning.sylvain.dev` quitte le joker Pangolin et répond en erreur jusqu'au premier déploiement). Depuis le dashboard, ou :

   ```bash
   # depuis le dépôt homelab : mise charge CLOUDFLARE_API_TOKEN et CLOUDFLARE_ACCOUNT_ID
   mise exec -- sh -c 'curl -sS -X POST -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -F branch=main \
     "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/planning-equipes/deployments" | jq .success'
   ```

5. **Recopier le jeton du beacon** : `mise exec -- tofu -chdir=tofu/planning output -raw web_analytics_token` remplace `A_REMPLACER_PAR_LE_JETON` dans `site/index.html` **et** `site/en/index.html` du dépôt `planning-equipes` (une PR ; son merge redéploie, le chemin `site/**` étant touché). L'identifiant du site, pour le tableau de bord ou l'API : `tofu output -raw web_analytics_site_tag`.
6. `mise run plan-planning` doit être vide, **sans** avertissement `beacon_token`.
7. Vérifier `curl -sI https://planning.sylvain.dev` (200, en-têtes de `_headers`) et `https://planning.sylvain.dev/en/`.
8. Appliquer `tofu/pangolin_config` pour le moniteur Uptime Kuma « Planning (vitrine) » (`external_monitors.tf`) : `mise exec -- tofu -chdir=tofu/pangolin_config plan`, qui ne doit montrer que ce moniteur, puis `apply`. Après le site, sinon il passe DOWN.

Si le site Web Analytics est un jour recréé (changement d'hôte…), le nouveau jeton fait réapparaître l'avertissement `beacon_token` : refaire l'étape 5.
