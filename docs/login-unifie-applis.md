# Login unifié : support OIDC des applis

> **Pilote Pocket ID** ([ADR 0030](adr/0030-pocket-id-fournisseur-identite-pilote.md), 2026-11-05) : Pocket ID
> remplace Authelia (0016, remplacée) comme fournisseur ; seul **Homebox** est branché, et seul le compte de
> Sylvain l'utilise. Le support des applis ci-dessous ne dépend pas du fournisseur, mais
> les passages « Avec Authelia » (`authorization_policy`, `claims_policy`) valent pour Pocket ID
> ainsi : les groupes autorisés se règlent dans le client Pocket ID, le claim `groups` exige le scope
> `groups` et porte les noms internes des groupes (voir [runbooks/pocket-id.md](runbooks/pocket-id.md)).
> Pocket ID n'a ni mot de passe ni TOTP : les « second facteur » de 0016 n'y existent pas.

Détail de l'[ADR 0016](adr/0016-login-unifie-oidc.md) (remplacée par 0030) : support
OIDC de chaque appli à la version déployée le 2026-10-29, effort, et ce qui
reste en dehors. Ce qui n'a pu être sourcé est marqué « à confirmer ».

| Appli (version) | OIDC | Source | Effort | Login local gardé |
|---|---|---|---|---|
| Homebox 0.27.1 (pilote) | natif, liaison par e-mail | [conf.go](https://github.com/sysadminsmedia/homebox/blob/v0.27.1/backend/internal/sys/config/conf.go) | faible | oui (`ALLOW_LOCAL_LOGIN`) ; chaque nouveau compte a son propre foyer, hors de l'invitation de groupe de [0014](adr/0014-homebox.md) : allowed groups, et effet de l'inscription fermée sur la création OIDC à confirmer |
| Immich v3.3.5 (branché, le foyer) | natif, réglé dans l'UI ; rôle par claim `immich_role` (groupe `immich-admin`), liaison par e-mail sans vérification, auto-register coupé ; mobile `app.immich:///oauth-callback` | [doc](https://docs.immich.app/administration/oauth) | faible | oui (`passwordLogin`) |
| Nextcloud 35.0.2 | `user_oidc` 8.11.0, groupes | [README](https://github.com/nextcloud/user_oidc/blob/v8.11.0/README.md) | moyen (uid à aligner) | oui (`/login?direct=1`) ; clients par login flow v2 non confirmé |
| TREK 5.0.1 (branché) | natif, admin par claim (`groups` contient `trek-admin`, relu à chaque connexion ; le dernier admin n'est jamais rétrogradé), liaison par e-mail vérifié et non saisi par le compte | [oidc.service.ts](https://github.com/liketrek/TREK/blob/v5.0.1/server/src/nest/oidc/oidc.service.ts) | faible | oui sauf `OIDC_ONLY` |
| HealthLog 1.46.5 (branché, Sylvain seul) | natif (`OIDC_ISSUER_URL`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`), pas de rôle par claim ; liaison : e-mail vérifié puis une connexion par mot de passe dans les 10 min | [sso.md](https://github.com/MBombeck/HealthLog/blob/v1.46.5/docs/self-hosting/sso.md) | faible | oui sauf `OIDC_ONLY` |
| Wishlist v0.69.0 (branché, le foyer) | natif, réglé dans l'UI (secret client saisi à la main, hors Ansible) ; rappel `/login`, PKCE, liaison par e-mail vérifié, pas de rôle | [config.ts](https://github.com/cmintey/wishlist/blob/v0.69.0/src/lib/server/config.ts) | faible | oui |
| Dawarich 1.19.0 (branché, le foyer) | natif ; `OIDC_REDIRECT_URI` à fixer (sans `APPLICATION_URL`, rappel en `http://localhost:3000`), `OIDC_PKCE_ENABLED`, `OIDC_AUTO_REGISTER=false` ; liaison par défi (mot de passe Dawarich), e-mail vérifié exigé | [oidc_config.rb](https://github.com/Freika/dawarich/blob/1.19.0/lib/oidc_config.rb) | faible | oui ; traceurs par clé d'API |
| Karakeep 0.34.1 (branché, le foyer) | natif par `OAUTH_*` (rôle karakeep) ; liaison par e-mail (`OAUTH_ALLOW_DANGEROUS_EMAIL_ACCOUNT_LINKING`), pas de rôle ; appli et extension : mot de passe ou clé d'API | [auth.ts](https://github.com/karakeep-app/karakeep/blob/v0.34.1/apps/web/server/auth.ts) | faible | **obligatoire** pour les clients |
| Papra 26.7.1 (branché, le foyer) | natif, better-auth `AUTH_PROVIDERS_CUSTOMS` (rôle papra), PKCE ; liaison par e-mail vérifié des deux côtés (`users.email_verified` à poser en base pour un compte créé par inscription), inscription fermée, pas de rôle | [setup-custom-oauth2](https://github.com/papra-hq/papra/blob/%40papra/app%4026.7.1/apps/docs/src/content/docs/03-guides/04-setup-custom-oauth2.mdx) | faible | oui |
| Yamtrack 0.26.3 (branché, le foyer) | natif, allauth `openid_connect` (rôle yamtrack), PKCE ; **liaison manuelle** depuis les réglages, `REGISTRATION=False` ferme l'OIDC aussi, pas de rôle | [social-auth.md](https://github.com/FuzzyGrim/Yamtrack/blob/v0.26.3/docs/social-auth.md) | faible | oui |
| MediaManager 1.12.3 (branché, essai) | natif `[auth.openid_connect]` (rôle mediamanager), sans PKCE ; liaison par e-mail **non vérifié**, **pas d'interrupteur d'inscription** (le groupe Pocket ID borne) ; admin par `admin_emails` à l'inscription | [router.py](https://github.com/maxdorninger/MediaManager/blob/v1.12.3/media_manager/auth/router.py) | faible | oui |
| Immich Power Tools 0.25.0 | par Immich (`OAUTH_ENABLED`, rappel `/api/auth/oauth/callback` à ajouter au client immich) ; **mais avec `IMMICH_API_KEY` posé, tout visiteur sans cookie agit comme le propriétaire de la clé** : l'OIDC n'apporte rien tant que la clé reste | [authorize.ts](https://github.com/immich-power-tools/immich-power-tools/blob/v0.25.0/src/pages/api/auth/oauth/authorize.ts) | moyen | — : non branché, réservé à Sylvain par le mur |
| Grocy 4.7.1, Jellystat 1.1.12, Enclosed 1.16.1, Immich Kiosk 0.45.2 | aucun (Grocy : en-tête de proxy seulement, qui coupe le login local) | code aux tags | — | **reste tel quel** : le mur Pangolin |
| Beszel 0.21.1 (branché, Sylvain seul) | OAuth2 PocketBase (fournisseur OIDC saisi dans l'admin PocketBase, secret par `tofu output -raw`), `USER_CREATION` à false : aucun compte créé | [doc](https://beszel.dev/guide/oauth) (latest) | faible | oui ; superuser Homepage à part |
| Immich Swipe (`sha-a9644ff`) | aucun : clé d'API Immich posée côté serveur par son nginx (`ansible/roles/immich/README.md`) | — | — | **reste tel quel** : le mur Pangolin suffit |
| Homepage v2.7.0 | porte OIDC sans rôles | [doc](https://github.com/gethomepage/homepage/blob/v2.7.0/docs/installation/index.md) | — | rien à faire : le mur suffit |
| BookStack 26.09 | `AUTH_METHOD=oidc`, **exclusif**, liaison par `external_auth_id` | [doc](https://www.bookstackapp.com/docs/admin/oidc-auth/) | moyen | **non** : en dernier |
| FreshRSS 1.30.4 | `mod_auth_openidc`, **exclusif** (`http_auth`) | [doc](https://freshrss.github.io/FreshRSS/en/admins/16_OpenID-Connect.html) | moyen | **non** ; API mobile hors OIDC |
| vmauth v1.155.0 | SSO OIDC open source depuis 1.153 | [vmauth.md](https://github.com/VictoriaMetrics/VictoriaMetrics/blob/v1.155.0/docs/victoriametrics/vmauth.md) | moyen | à tester : `jwt` mêlé aux comptes Basic des agents non confirmé |
| Paperless-ngx 3.3 | allauth OIDC, groupes | [configuration.md](https://github.com/paperless-ngx/paperless-ngx/blob/v3.3.4/docs/configuration.md) | — | en pause : à la reprise |
| Jellyfin 12.4 | plugin communautaire (fork K0lin), Quick Connect pour les TV | [v5.1.0](https://github.com/K0lin/jellyfin-plugin-sso/releases/tag/v5.1.0) | — | **reste tel quel** |
| Monica 3.7.0, Speedtest Tracker 1.15.1, ntfy v2.34.0, Uptime Kuma 2.5.8 | aucun ([ntfy #1596](https://github.com/binwiederhier/ntfy/issues/1596), [Kuma #6539](https://github.com/louislam/uptime-kuma/issues/6539)) | code aux tags | — | **reste tel quel** : le mur Pangolin, puis leur compte |
| Flip Planning, Betisier, Promptoramix | Keycloak à soi / public | — | — | **reste tel quel** : autres utilisateurs |

**Avec Authelia** : les « allowed groups » ci-dessus (Homebox)
deviennent l'`authorization_policy` du client (`subject: group:<appli>`, en
`two_factor`) ; une appli qui lit les groupes dans l'ID token plutôt qu'au
userinfo a besoin d'une `claims_policy` (Authelia 4.39 ne les y met plus par
défaut), à vérifier appli par appli au branchement.

**Ordre** : vérifier la clé EE ; Authelia, passkeys et TOTP ; **pilote Homebox** ;
mur Pangolin (comptes recréés côté IdP) ; Immich, TREK, Wishlist, Dawarich,
Beszel, Nextcloud, Karakeep ; BookStack, FreshRSS, vmauth
en dernier, si le gain vaut le login local perdu.
