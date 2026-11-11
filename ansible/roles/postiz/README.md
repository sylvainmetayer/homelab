# postiz

[Postiz](https://github.com/gitroomhq/postiz-app) (v2.25.3) sur
**https://posts.sylvain.cloud** : planification de publications sur les réseaux
sociaux, pour le foyer. Hôte **flip**, `dc@postiz`, quatre conteneurs : `postiz`
(nginx, backend, frontend et orchestrateur ; réseaux `newt` et `internal`),
`postiz-db` (PostgreSQL), `postiz-redis`, `postiz-temporal` (réseau `internal`,
sans sortie). Derrière le SSO de Pangolin (rôle `postiz`, groupe Pocket ID du
même nom), puis la connexion à l'appli par Pocket ID.

## Mémoire : flip est juste

Premier déploiement le 2026-11-11 : flip (4 Gio) est tombée à 479 Mio
disponibles et 1,1 Gio de swap, Postiz a été arrêté. La démo de Flip Planning
(~540 Mio) est depuis en pause pour lui laisser la place
(`demo_planning_enabled: false`, `host_vars/flip`). Mesuré ensuite, quatre
minutes après le démarrage, sans compte ni publication : `postiz` 1,26 Gio,
`postiz-db` 161 Mio, `postiz-temporal` 172 Mio, `postiz-redis` 15 Mio ;
768 Mio disponibles sur l'hôte, production à 366 Mio.

**Les deux ne tiennent pas ensemble** : reprendre la démo demande d'arrêter
Postiz (`postiz_enabled: false`), ou de le déplacer sur la VM docker. Un
solveur de production monte vers 1 Gio : flip passera alors par le swap.

## Écarts avec le compose amont

Le [compose amont](https://github.com/gitroomhq/postiz-docker-compose) lance
neuf conteneurs ; flip a 4 Gio, partagés avec la production de Flip Planning.

- **Pas d'Elasticsearch** : `ENABLE_ES=false`, la visibilité de Temporal est en
  SQL. Postiz n'ajoute que deux attributs de recherche de type texte
  (`temporal.register.ts`), PostgreSQL en accepte trois, à condition
  qu'auto-setup ne crée pas ses attributs d'exemple
  (`SKIP_ADD_CUSTOM_SEARCH_ATTRIBUTES`). Sans ce réglage, `postiz` bouclait sur
  « cannot have more than 3 search attribute of type Text » (flip,
  2026-11-11) ; avec, le backend démarre (vu le même jour).
- **Un seul PostgreSQL** : Temporal crée ses bases `temporal` et
  `temporal_visibility` dans celui de Postiz (même utilisateur, superutilisateur
  de l'instance).
- Pas de `temporal-ui` ni de `temporal-admin-tools` : en cas de besoin,
  `docker exec postiz-temporal temporal workflow list --address temporal:7233`.
- Redis sans persistance : cache et limites de débit seulement.
- `cpu_shares: 512` sur `postiz` et `temporal` : ils cèdent le CPU à Flip
  Planning. Les plafonds mémoire ne sont **pas mesurés** (à recaler sur
  `mem_report`) ; leur somme (3,3 Gio) dépasse ce que flip a de libre, c'est
  l'occupation réelle qu'il faut regarder la première semaine.

## Connexion (Pocket ID)

`POSTIZ_OAUTH_*`, rendus quand le client `postiz` est dans le state de
`tofu/pangolin_config` (`pocket_id.tf`). Rappel `https://posts.sylvain.cloud/settings`,
sans PKCE. Le compte Postiz est créé au premier login, lié par e-mail ; le
premier a sa propre organisation, les suivants aussi : les inviter dans la
tienne depuis Settings → Team. `DISABLE_REGISTRATION=true` ferme l'inscription
locale dès qu'une organisation existe : **te connecter le premier**.

**Pas de secours local éprouvé** : un compte créé par OIDC n'a pas de mot de
passe. Les mails partent par le compte Infomaniak partagé (`pangolin_smtp_*`,
`EMAIL_*` du `.env`) : « mot de passe oublié » (`/auth/forgot`) devrait en
poser un, **non essayé**. Si Pocket ID est en panne, c'est d'abord lui qu'on
dépanne (`docs/runbooks/pocket-id.md`, « Secours »).

Changer `pangolin_smtp_pass` : relancer aussi `flip.yml --tags postiz`.

## Médias : `/uploads/*` est public

Instagram, Threads, TikTok et Facebook (photos) téléchargent le média depuis
leurs serveurs : Pangolin ouvre `/uploads/*` sans SSO et depuis tout pays
(`tofu/pangolin_config/website_postiz.tf`). Un média est donc lisible par qui
connaît son URL (nom aléatoire de 32 caractères hexadécimaux), dès l'envoi,
publié ou non. L'image est dans `path_bypass_images.json` : jamais d'automerge
Renovate, `var/docker/nginx.conf` et `local.storage.ts` sont relus à chaque
montée.

## Réseaux sociaux

Les clés vont dans **une** clé SOPS, `postiz_social_env`, un dictionnaire
`VARIABLE: valeur` rendu tel quel dans le `.env` ; une valeur vide laisse le
réseau éteint. Bluesky et Mastodon (instance par défaut) se branchent depuis
l'interface, sans clé. Créer la clé (une fois), puis son entrée dans
`secrets/secrets-rotation.yaml` (`kind: application`) :

```bash
sops set secrets/ansible.sops.yaml '["postiz_social_env"]' '{"FACEBOOK_APP_ID":"","FACEBOOK_APP_SECRET":"","INSTAGRAM_APP_ID":"","INSTAGRAM_APP_SECRET":"","THREADS_APP_ID":"","THREADS_APP_SECRET":"","YOUTUBE_CLIENT_ID":"","YOUTUBE_CLIENT_SECRET":"","LINKEDIN_CLIENT_ID":"","LINKEDIN_CLIENT_SECRET":"","X_API_KEY":"","X_API_SECRET":"","TIKTOK_CLIENT_ID":"","TIKTOK_CLIENT_SECRET":"","PINTEREST_CLIENT_ID":"","PINTEREST_CLIENT_SECRET":""}'
```

Ensuite `sops secrets/ansible.sops.yaml` pour remplir, puis
`ansible-playbook flip.yml --tags postiz`. L'app développeur se crée à la main
chez chaque fournisseur, avec l'URL de redirection exacte ci-dessous (guide :
`https://docs.postiz.com/providers/<réseau>`).

| Réseau | Où créer l'app | URL de redirection | Variables | À savoir |
|---|---|---|---|---|
| Facebook (pages) | developers.facebook.com, app « Business » | `https://posts.sylvain.cloud/integrations/social/facebook` | `FACEBOOK_APP_ID`, `FACEBOOK_APP_SECRET` | droits `pages_show_list`, `pages_manage_posts`, `pages_manage_engagement`, `pages_read_engagement` ; sans revue Meta, seuls les comptes ajoutés à l'app (rôles) publient |
| Instagram (via Facebook) | la même app Meta | `https://posts.sylvain.cloud/integrations/social/instagram` | celles de Facebook | compte Instagram professionnel relié à une page ; droits `instagram_basic`, `instagram_content_publish`, `instagram_manage_comments`, `instagram_manage_insights`, `pages_show_list`, `pages_read_engagement` |
| Instagram (autonome) | la même app Meta, produit « Instagram » | `https://posts.sylvain.cloud/integrations/social/instagram-standalone` | `INSTAGRAM_APP_ID`, `INSTAGRAM_APP_SECRET` | sans page Facebook ; identifiants propres au produit Instagram, pas ceux de l'app |
| Threads | la même app Meta, cas d'usage « Threads API » | `https://posts.sylvain.cloud/integrations/social/threads` | `THREADS_APP_ID`, `THREADS_APP_SECRET` | identifiants de l'onglet Threads ; mêmes URL pour « Uninstall » et « Delete » (le formulaire les exige) ; s'inviter comme testeur Threads |
| YouTube | console.cloud.google.com : projet, API « YouTube Data API v3 », client OAuth « Application Web » | `https://posts.sylvain.cloud/integrations/social/youtube` | `YOUTUBE_CLIENT_ID`, `YOUTUBE_CLIENT_SECRET` | écran de consentement en « test » : s'ajouter comme utilisateur test, le jeton expire alors au bout de 7 jours ; « en production » pour l'éviter |
| LinkedIn (profil, page) | linkedin.com/developers | `https://posts.sylvain.cloud/integrations/social/linkedin` et `…/linkedin-page` | `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET` | produits « Share on LinkedIn », « Sign In with LinkedIn using OpenID Connect » et « Advertising API » (formulaire ; sans lui pas de renouvellement de jeton, et un scope manquant donne `NotEnoughScopes`) |
| X | developer.x.com, app avec « User authentication » (OAuth 1.0a, lecture et écriture) | `https://posts.sylvain.cloud/integrations/social/x` | `X_API_KEY`, `X_API_SECRET` | URL non relue dans le guide amont (page absente le 2026-11-11), même schéma que les autres ; offre gratuite très limitée |
| TikTok | developers.tiktok.com, produits « Login Kit » et « Content Posting API » | `https://posts.sylvain.cloud/integrations/social/tiktok` | `TIKTOK_CLIENT_ID`, `TIKTOK_CLIENT_SECRET` | sans audit TikTok, publication en privé seulement ; vérification du domaine pour l'envoi par URL (`/uploads/`) |
| Pinterest | developers.pinterest.com | `https://posts.sylvain.cloud/integrations/social/pinterest` | `PINTEREST_CLIENT_ID`, `PINTEREST_CLIENT_SECRET` | accès « Standard » à demander pour publier hors bac à sable |

Ces redirections sont des allers-retours de ton navigateur, déjà passé par le
SSO : rien d'autre que `/uploads/*` n'est ouvert.

## Sauvegarde

Borg `postiz` (sous-compte Storage Box de flip) : `uploads`, `compose.yaml`,
`.env` et le dump des trois bases (`postiz`, `temporal`, `temporal_visibility` :
les publications planifiées sont des workflows Temporal en attente).
Restauration : les trois dumps dans un PostgreSQL vide, **avant** de démarrer
`temporal`.

## Ordre au premier déploiement

1. `tofu/pangolin_config` : rôle, ressource, moniteurs, client et groupe Pocket
   ID (skill `pangolin-config-plan`).
2. `ansible-playbook flip.yml --tags postiz` (lit l'URL push et le client OIDC
   dans le state). Premier démarrage long : Temporal crée ses schémas, puis
   Postiz migre sa base (sonde : `start_period` de 120 s).
3. Pocket ID : s'ajouter au groupe `postiz`, puis premier login.
4. `ansible-playbook docker.yml --tags homepage` pour le lien sur Homepage.
