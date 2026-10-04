# tofu/ref

Infra du site de parrainage [ref.sylvain.dev](https://ref.sylvain.dev) (code : dépôt `sylvainmetayer/ref`, local `~/Documents/ref`).

| Ressource | Rôle |
|---|---|
| `github_repository.ref` | Dépôt public, vide (poussé à la main), issues ouvertes (lien « Un code ne marche plus ? ») |
| `github_app_installation_repository.cloudflare` | Accès de l'app GitHub Cloudflare au dépôt (si `cloudflare_github_installation_id` est renseigné) |
| `github_branch_protection.ref_main` | Ni suppression ni force-push sur `main`, propriétaire compris ; pas de PR obligatoire (Sveltia CMS commite directement) |
| `github_workflow_repository_permissions.ref` | Jeton des workflows en lecture seule par défaut |
| `github_repository_dependabot_security_updates.ref` | PR Dependabot pour les failles connues |
| `cloudflare_pages_project.ref` | Build `npm run build` → `_site`, déploiement à chaque push, previews sur les branches |
| `cloudflare_pages_domain.ref` | Domaine personnalisé `ref.sylvain.dev` |
| `ovh_domain_zone_record.ref` | CNAME `ref` → `<projet>.pages.dev` (prime sur le joker `*.sylvain.dev` de `tofu/dns`) |
| `cloudflare_web_analytics_site.ref` | Pages vues ; jeton du beacon en sortie `web_analytics_token`, comparé au plan à `site.json` du dépôt `ref` (`check "beacon_token"`) |

La vérification Google Search Console de `sylvain.dev` (TXT à l'apex) vit dans `tofu/dns` : elle couvre tout le domaine, pas seulement ce site.

Les bindings Pages (dataset Analytics Engine `ref_events`) sont déclarés dans le `wrangler.toml` du dépôt `ref`, pas ici.

## Prérequis

1. **Jeton API Cloudflare** (*My Profile → API Tokens → Create Custom Token*), portée : le compte uniquement :
   - Account → **Cloudflare Pages** → Edit
   - Account → **Account Analytics** → Read (pour `mise run stats` côté `ref`)
   - Web Analytics : la permission de gestion des sites Web Analytics (RUM) → Edit
2. Le stocker avec l'ID de compte (visible dans l'URL du dashboard) :

   ```bash
   sops set secrets.sops.yaml '["CLOUDFLARE_API_TOKEN"]' '"<jeton>"'
   sops set secrets.sops.yaml '["CLOUDFLARE_ACCOUNT_ID"]' '"<id>"'
   ```

3. **Application GitHub Cloudflare** (« Cloudflare Workers and Pages ») :
   - **première installation, à la main** (consentement navigateur, aucune API) : *Workers & Pages → Create → Pages → Connect to Git* ;
   - si elle est installée en mode **« All repositories »** : rien d'autre à faire ;
   - en mode **« Only select repositories »** : Terraform ajoute le dépôt (`github_app_installation_repository.cloudflare`). Renseigner l'ID visible dans l'URL `https://github.com/settings/installations/<id>` :

     ```bash
     export TF_VAR_cloudflare_github_installation_id=<id>
     ```

     ⚠️ Cet appel d'API (`PUT /user/installations/{id}/repositories/{repo_id}`) n'accepte qu'un **PAT classique avec le scope `repo`** : le jeton de `gh auth token` ne suffit pas. Pour cet apply, `export GITHUB_TOKEN=<PAT classique>`.

4. **Workers Analytics Engine activé sur le compte** (une fois, dashboard uniquement : *Workers → Analytics Engine*). Sans lui, le build réussit mais la publication des Functions échoue : `You need to enable Analytics Engine`.
5. Le **premier déploiement** ne part pas tout seul si le dépôt a été poussé avant que l'app GitHub y ait accès : relancer depuis le dashboard ou via `POST …/pages/projects/ref/deployments` (`branch=main`).

## Utilisation

```bash
export GITHUB_TOKEN="$(gh auth token)"
mise run plan-ref    # init puis plan
mise run apply-ref
```

mise charge `secrets.sops.yaml` (identifiants S3 du backend, OVH, `CLOUDFLARE_API_TOKEN` lu tel quel par le provider) ; les tâches passent `CLOUDFLARE_ACCOUNT_ID` en `TF_VAR_cloudflare_account_id`.

## Ordre des opérations

1. `tofu apply` crée le dépôt vide, mais **le projet Pages a besoin d'un dépôt avec du contenu** : si la création échoue, pousser d'abord puis réappliquer :

   ```bash
   # depuis la racine du dépôt homelab, où mise charge les identifiants du backend
   git -C "$HOME/Documents/ref" remote add origin "$(mise exec -- tofu -chdir=tofu/ref output -raw repository_ssh_url)"
   git -C "$HOME/Documents/ref" push -u origin main
   ```

2. Reporter `tofu output -raw web_analytics_token` dans `src/_data/site.json` (`cfBeaconToken`) du dépôt `ref`. Tant que ce n'est pas fait, ou si le site Web Analytics est recréé, `tofu plan` affiche un avertissement `beacon_token`.
3. Sur sylvain.dev (Netlify), rediriger l'ancienne page : `/parrainage  https://ref.sylvain.dev/  301`.
4. Créer le jeton fine-grained GitHub pour Sveltia CMS (dépôt `ref`, *Contents: Read and write*) — pas de ressource provider pour ça.
