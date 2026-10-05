# tofu/site

Infra du site personnel [sylvain.dev](https://sylvain.dev) (code : dépôt `sylvainmetayer/site`, Eleventy + Sveltia CMS), migré de Netlify vers Cloudflare Pages sur le modèle de [`tofu/ref`](../ref/README.md).

| Ressource | Rôle |
|---|---|
| `data.github_repository.site` | Dépôt existant, lu seulement (pas géré ici) |
| `github_app_installation_repository.cloudflare` | Accès de l'app GitHub Cloudflare au dépôt (si `cloudflare_github_installation_id` est renseigné) |
| `github_actions_secret.pages_deploy_hook` | Secret `CLOUDFLARE_PAGES_DEPLOY_HOOK` du dépôt site, pour le build quotidien (si `SITE_PAGES_DEPLOY_HOOK` est dans `secrets.sops.yaml`) |
| `github_actions_secret.sonar_token` | Secret `SONAR_TOKEN` du dépôt site, pour le workflow SonarCloud (si `SITE_SONAR_TOKEN` est dans `secrets.sops.yaml`) |
| `check.daily_build_deploy_hook` | Avertit au plan si `SITE_PAGES_DEPLOY_HOOK` manque (Daily Build en échec) |
| `cloudflare_pages_project.site` | Projet `sylvain-dev` : build `npm run production` → `dist`, déploiement à chaque push, previews sur les branches. Le site déduit `ELEVENTY_ENV` de `CF_PAGES_BRANCH` ; seule variable : `WEBMENTION_IO_TOKEN` en production (si `SITE_WEBMENTION_IO_TOKEN` est dans `secrets.sops.yaml`) |
| `cloudflare_pages_domain.site` | Domaine personnalisé `www.sylvain.dev` |
| `cloudflare_web_analytics_site.site` | Site Web Analytics existant, importé (même jeton, historique conservé) ; jeton en sortie `web_analytics_token` |
| `ovh_domain_zone_record.www` | CNAME `www` → `<projet>.pages.dev` (prime sur le joker `*.sylvain.dev` de `tofu/dns`) |

L'enregistrement A de l'apex `sylvain.dev` vers Pangolin n'est pas ici mais dans `tofu/dns/pangolin.tf`, à côté du joker (`ovh_domain_zone_record.sylvain_dev_root`, variable `sylvain_dev_apex_to_pangolin`).

## Pourquoi www et une redirection

Cloudflare Pages n'accepte un domaine apex que si la zone DNS est chez Cloudflare. La zone `sylvain.dev` reste chez OVH (joker Pangolin, `ref`, TXT…), donc :

- le site est servi sur `www.sylvain.dev`, par un CNAME comme `ref.sylvain.dev` ;
- l'apex `sylvain.dev` pointe vers Pangolin, dont Traefik répond par une 301 vers `https://www.sylvain.dev` en gardant le chemin (`pangolin_domain_redirects` dans `ansible/host_vars/pangolin/variables.yaml`, routeurs du fichier dynamique `traefik_dynamic_config.yml.j2`) ;
- sur l'apex, `/service-worker.js` n'est pas redirigé : Traefik sert à la place `/service-worker-retired.js` de www, qui désinstalle le service worker cache-first de l'ancien site. Un navigateur refuse de mettre à jour un service worker derrière une redirection, l'ancien resterait actif et servirait son cache.

Le certificat de l'apex est obtenu par Let's Encrypt (défi HTTP) : il faut que l'apex pointe déjà vers Pangolin quand Traefik charge le routeur (étape 5).

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

L'apex reste servi par Netlify jusqu'à l'étape 5. Le dépôt `site` garde un `netlify.toml` de transition : fusionner sa PR avant la bascule est sans risque, Netlify construit et sert le nouveau site.

1. **Web Analytics existant** : avant le premier apply, importer le site créé à la main (jeton `b127465e…`, celui du `site.json`) pour garder l'historique et le jeton. Son identifiant (*site tag*) est dans le dashboard, *Analytics & Logs → Web Analytics → Manage site*.

   ```bash
   mise exec -- tofu -chdir=tofu/site import cloudflare_web_analytics_site.site '<account_id>/<site_tag>'
   ```

   Le plan ne doit montrer qu'un changement d'hôte (`sylvain.dev` → `www.sylvain.dev`), pas un remplacement. S'il propose de le recréer, le jeton changerait : le reporter alors dans `src/_data/site.json` (`cfBeaconToken`) du dépôt `site`.
2. **Pages + www** : si un enregistrement `www` existe chez OVH (CNAME vers Netlify, fait à la main), le supprimer dans le manager OVH juste avant `tofu apply` : OVH refuse un second CNAME sur le même nom. `www.sylvain.dev` ne répond plus jusqu'à ce que Cloudflare valide le domaine (quelques minutes) ; l'apex n'est pas touché.
   - Vérifier `curl -sI https://www.sylvain.dev/` puis une preview de branche (`<branche>.sylvain-dev.pages.dev`).
3. **Build quotidien** : créer un deploy hook sur la branche `main` (*Workers & Pages → sylvain-dev → Settings → Builds → Deploy hooks*). Le workflow du dépôt `site` déclenche Netlify et Pages tant que les deux secrets existent.

   ```bash
   sops set secrets.sops.yaml '["SITE_PAGES_DEPLOY_HOOK"]' '"<url du hook>"'
   mise exec -- tofu -chdir=tofu/site apply
   ```

4. **Fusionner la PR du dépôt `site`** si ce n'est pas déjà fait (Pages et Netlify construisent `main`).
5. **Apex**, à enchaîner sans attendre :
   1. supprimer chez OVH les enregistrements A/AAAA de l'apex qui pointent vers Netlify (ne toucher ni aux MX ni aux TXT) ;
   2. `mise exec -- tofu -chdir=tofu/dns apply -var sylvain_dev_apex_to_pangolin=true`, puis passer la valeur par défaut de la variable à `true` dans `tofu/dns/variables.tf` ;
   3. vérifier que l'apex résout vers Pangolin (`dig +short sylvain.dev`), puis depuis `ansible/` : `ansible-playbook -i inventory/hosts pangolin.yaml --tags pangolin`. Le fichier dynamique est rechargé à chaud et Traefik demande le certificat de l'apex.

   Entre 5.1 et 5.3, l'apex arrive sur Pangolin sans routeur (404, certificat par défaut) pour les résolveurs qui ont déjà la nouvelle réponse : quelques minutes. Si l'apex sert encore le certificat par défaut de Traefik après le playbook (défi HTTP raté, par exemple DNS pas encore propagé), Traefik ne réessaie pas seul : `ssh pangolin.sylvain.cloud docker restart traefik`.
6. **Supervision** : `tofu apply` dans `tofu/pangolin_config` (moniteurs Uptime Kuma `Blog` sur www et `Blog (apex)`).
7. **Netlify** : supprimer le site Netlify, le secret `netlify_webhook` et le `netlify.toml` de transition du dépôt `site`.
8. **Sveltia CMS** : plus de fournisseur OAuth Netlify. Créer un fine-grained PAT limité au dépôt `site` (*Contents: Read and write*, *Pull requests: Read and write* pour le workflow éditorial) et utiliser « Sign In Using Access Token ».

## Secrets du dépôt site

Trois clés de `secrets.sops.yaml` (racine du dépôt), toutes optionnelles : sans elles, le plan ne crée rien (seul le deploy hook manquant y est signalé, par un avertissement).

| Clé sops | Ce que l'apply en fait | Utilisée par |
|---|---|---|
| `SITE_PAGES_DEPLOY_HOOK` | secret GitHub `CLOUDFLARE_PAGES_DEPLOY_HOOK` | workflow *Daily Build* (articles programmés, nouvelles webmentions) |
| `SITE_WEBMENTION_IO_TOKEN` | variable `WEBMENTION_IO_TOKEN` (secret, production) du projet Pages | `src/_data/webmentions.js` au build |
| `SITE_SONAR_TOKEN` | secret GitHub `SONAR_TOKEN` | workflow *SonarCloud* |

### 1. Obtenir les valeurs

- **Build quotidien** : *Workers & Pages → sylvain-dev → Settings → Builds → Deploy hooks → Add deploy hook*, nom `daily-build`, branche `main`. Copier l'URL (`https://api.cloudflare.com/client/v4/pages/webhooks/deploy_hooks/…`). Pas d'API documentée pour le créer, d'où l'étape manuelle.
- **Webmentions** : se connecter sur <https://webmention.io> avec `www.sylvain.dev`, puis copier l'*API Key* de <https://webmention.io/settings>.
- **SonarCloud** : sur <https://sonarcloud.io>, *+ → Analyze new project*, organisation `sylvainmetayer-github`, dépôt `site` (clé de projet `sylvainmetayer_site`, celle de `sonar-project.properties`). Dans le projet, *Administration → Analysis Method* : désactiver l'*Automatic Analysis*. Puis *My Account → Security → Generate Tokens*, type *Project Analysis Token* sur `sylvainmetayer_site`, sans expiration ou avec un rappel.

### 2. Les ajouter à sops

Depuis la racine du dépôt homelab (la clé age perso ou pro doit être disponible, comme pour `tofu plan`). `sops set` chiffre la valeur en place, sans fichier en clair sur le disque ; la valeur est une chaîne JSON, d'où les guillemets doubles à l'intérieur des simples :

```bash
sops set secrets.sops.yaml '["SITE_PAGES_DEPLOY_HOOK"]' '"https://api.cloudflare.com/client/v4/pages/webhooks/deploy_hooks/<id>"'
sops set secrets.sops.yaml '["SITE_WEBMENTION_IO_TOKEN"]' '"<api key webmention.io>"'
sops set secrets.sops.yaml '["SITE_SONAR_TOKEN"]' '"<jeton SonarCloud>"'
```

Pour ne pas laisser les jetons dans l'historique du shell, préfixer chaque ligne d'une espace (si `HISTCONTROL` contient `ignorespace`), ou passer par `sops edit secrets.sops.yaml` et ajouter les trois lignes `CLE: valeur` dans l'éditeur.

Vérifier (noms seulement, sans afficher les valeurs) :

```bash
sops -d secrets.sops.yaml | grep -oE '^SITE_[A-Z_]+'
```

Puis commiter `secrets.sops.yaml` (il reste chiffré).

### 3. Appliquer

```bash
export GITHUB_TOKEN="$(gh auth token)"
mise exec -- tofu -chdir=tofu/site plan    # 2 secrets GitHub à créer, projet Pages modifié, plus d'avertissement
mise exec -- tofu -chdir=tofu/site apply
mise exec -- tofu -chdir=tofu/site plan    # doit être vide
```

Si le second plan propose encore de réécrire `WEBMENTION_IO_TOKEN` (valeur `secret_text` non renvoyée par l'API), ajouter `ignore_changes = [deployment_configs]` au projet Pages.

### 4. Vérifier

```bash
gh secret list -R sylvainmetayer/site                          # CLOUDFLARE_PAGES_DEPLOY_HOOK et SONAR_TOKEN
gh workflow run daily_build.yml -R sylvainmetayer/site          # déclenche un build Pages de main
```

Le build lancé par le hook prend la nouvelle variable : les réactions apparaissent sous les articles qui en ont. Sur la prochaine PR du site, le job *SonarCloud* analyse au lieu d'afficher « SONAR_TOKEN absent ».

## Vérifications

```bash
curl -sI https://www.sylvain.dev/ | head -1                              # 200 servi par Cloudflare
curl -sI https://sylvain.dev/article/ansible/ | grep -i location           # https://www.sylvain.dev/article/ansible/
curl -sI https://sylvain.dev/service-worker.js | head -1                   # 200, pas de redirection
curl -s https://sylvain.dev/service-worker.js | head -1                    # « Retires the service worker… »
curl -sI https://www.sylvain.dev/blog/ | grep -i location                  # _redirects du site : /articles/
```
