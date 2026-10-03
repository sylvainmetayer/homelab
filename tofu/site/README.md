# tofu/site

Infra du site personnel [sylvain.dev](https://sylvain.dev) (code : dépôt `sylvainmetayer/site`, Eleventy + Sveltia CMS), migré de Netlify vers Cloudflare Pages sur le modèle de [`tofu/ref`](../ref/README.md).

| Ressource | Rôle |
|---|---|
| `data.github_repository.site` | Dépôt existant, lu seulement (pas géré ici) |
| `github_app_installation_repository.cloudflare` | Accès de l'app GitHub Cloudflare au dépôt (si `cloudflare_github_installation_id` est renseigné) |
| `github_actions_secret.pages_deploy_hook` | Secret `CLOUDFLARE_PAGES_DEPLOY_HOOK` du dépôt site, pour le build quotidien (si `SITE_PAGES_DEPLOY_HOOK` est dans `secrets.sops.yaml`) |
| `cloudflare_pages_project.site` | Projet `sylvain-dev` : build `npm run production` → `dist`, déploiement à chaque push, previews sur les branches, `ELEVENTY_ENV` par environnement |
| `cloudflare_pages_domain.site` | Domaine personnalisé `www.sylvain.dev` |
| `cloudflare_web_analytics_site.site` | Pages vues ; jeton du beacon en sortie `web_analytics_token` |
| `ovh_domain_zone_record.www` | CNAME `www` → `<projet>.pages.dev` (prime sur le joker `*.sylvain.dev` de `tofu/dns`) |
| `ovh_domain_zone_record.apex` | A `sylvain.dev` → IP de Pangolin, si `apex_to_pangolin = true` |

## Pourquoi www et une redirection

Cloudflare Pages n'accepte un domaine apex que si la zone DNS est chez Cloudflare. La zone `sylvain.dev` reste chez OVH (joker Pangolin, `ref`, TXT…), donc :

- le site est servi sur `www.sylvain.dev`, par un CNAME comme `ref.sylvain.dev` ;
- l'apex `sylvain.dev` pointe vers Pangolin, dont Traefik répond par une 301 vers `https://www.sylvain.dev` en gardant le chemin (`pangolin_domain_redirects` dans `ansible/host_vars/pangolin/variables.yaml`, routeurs du fichier dynamique `traefik_dynamic_config.yml.j2`). Le certificat de l'apex est obtenu par Let's Encrypt (défi HTTP) une fois l'enregistrement A en place.

## Prérequis

Les mêmes que [`tofu/ref`](../ref/README.md#prérequis) :

1. `CLOUDFLARE_API_TOKEN` et `CLOUDFLARE_ACCOUNT_ID` dans `secrets.sops.yaml` (le jeton de `ref` convient : *Cloudflare Pages Edit* et *Web Analytics Edit*).
2. L'app GitHub « Cloudflare Workers and Pages » avec accès au dépôt `site` : rien à faire en mode « All repositories », sinon `export TF_VAR_cloudflare_github_installation_id=<id>` et un PAT classique (scope `repo`) dans `GITHUB_TOKEN` pour cet apply.

## Utilisation

```bash
export GITHUB_TOKEN="$(gh auth token)"
mise exec -- tofu -chdir=tofu/site init
mise exec -- tofu -chdir=tofu/site plan
```

`mise exec` charge `secrets.sops.yaml` (identifiants S3 du backend et OVH).

## Ordre de la bascule

L'apex reste servi par Netlify jusqu'à l'étape 4 : pas de coupure.

1. **Enregistrement `www` existant** : s'il y en a un chez OVH (CNAME vers Netlify, fait à la main), le supprimer dans le manager OVH. OVH refuse un second CNAME sur le même nom, et le joker Pangolin couvre `www` en attendant.
2. **Pages + www** : `tofu apply` (avec `apex_to_pangolin = false`, la valeur par défaut). Le projet construit `main` et `www.sylvain.dev` devient actif après validation du domaine par Cloudflare.
   - Reporter `tofu output -raw web_analytics_token` dans `src/_data/site.json` (`cfBeaconToken`) du dépôt `site`.
   - Vérifier une preview de branche du dépôt `site` (`<branche>.sylvain-dev.pages.dev`), puis fusionner la PR de migration côté `site`.
3. **Redirection Traefik** : `ansible-playbook -i inventory/hosts pangolin.yaml --tags pangolin` depuis `ansible/` (fichier dynamique rechargé à chaud, pas de redémarrage).
4. **Apex** : supprimer chez OVH les enregistrements A/AAAA de l'apex qui pointent vers Netlify (ne toucher ni aux MX ni aux TXT), puis `tofu apply -var apex_to_pangolin=true` et passer la valeur par défaut de la variable à `true` dans `variables.tf`.
5. **Supervision** : `tofu apply` dans `tofu/pangolin_config` (moniteurs Uptime Kuma `Blog` sur www et `Blog (apex)`).
6. **Build quotidien** : créer un deploy hook sur la branche `main` (*Workers & Pages → sylvain-dev → Settings → Builds → Deploy hooks*), puis :

   ```bash
   sops set secrets.sops.yaml '["SITE_PAGES_DEPLOY_HOOK"]' '"<url du hook>"'
   mise exec -- tofu -chdir=tofu/site apply
   ```

7. **Netlify** : supprimer le site Netlify, le secret `netlify_webhook` et le `netlify.toml` de transition du dépôt `site` (gardé jusque-là pour que Netlify continue de construire et de servir l'apex).
8. **Sveltia CMS** : plus de fournisseur OAuth Netlify. Créer un fine-grained PAT limité au dépôt `site` (*Contents: Read and write*, *Pull requests: Read and write* pour le workflow éditorial) et utiliser « Sign In Using Access Token ».

## Vérifications

```bash
curl -sI https://www.sylvain.dev/ | head -1                 # 200 servi par Cloudflare
curl -sI https://sylvain.dev/article/ansible/ | grep -i location   # https://www.sylvain.dev/article/ansible/
curl -sI https://www.sylvain.dev/blog/ | grep -i location          # _redirects du site : /articles/
```
