# Login unifié : support OIDC des applis

Détail de l'[ADR 0016](adr/0016-login-unifie-oidc.md) (« proposée ») : support
OIDC de chaque appli à la version déployée le 2026-10-29, effort, et ce qui
reste en dehors. Ce qui n'a pu être sourcé est marqué « à confirmer ».

| Appli (version) | OIDC | Source | Effort | Login local gardé |
|---|---|---|---|---|
| Homebox 0.27.1 (pilote) | natif, liaison par e-mail | [conf.go](https://github.com/sysadminsmedia/homebox/blob/v0.27.1/backend/internal/sys/config/conf.go) | faible | oui (`ALLOW_LOCAL_LOGIN`) ; chaque nouveau compte a son propre foyer, hors de l'invitation de groupe de [0014](adr/0014-homebox.md) : allowed groups, et effet de l'inscription fermée sur la création OIDC à confirmer |
| Immich v3.3.5 | natif, rôle et quota par claim, appli mobile OK | [doc](https://docs.immich.app/administration/oauth) | faible | oui (`passwordLogin`) |
| Nextcloud 35.0.2 | `user_oidc` 8.11.0, groupes | [README](https://github.com/nextcloud/user_oidc/blob/v8.11.0/README.md) | moyen (uid à aligner) | oui (`/login?direct=1`) ; clients par login flow v2 non confirmé |
| TREK 5.0.0 | natif, admin par claim | [oidc.service.ts](https://github.com/liketrek/TREK/blob/v5.0.0/server/src/nest/oidc/oidc.service.ts) | faible | oui sauf `OIDC_ONLY` |
| HealthLog 1.46.5 | natif (`OIDC_ISSUER_URL`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`) | [sso.md](https://github.com/MBombeck/HealthLog/blob/v1.46.5/docs/self-hosting/sso.md) | faible | oui sauf `OIDC_ONLY` |
| Wishlist v0.69.0 | natif, réglé dans l'UI (secret client saisi à la main, hors Ansible) | [config.ts](https://github.com/cmintey/wishlist/blob/v0.69.0/src/lib/server/config.ts) | faible | oui |
| Dawarich 1.19.0 | natif, liaison par défi | [oidc_config.rb](https://github.com/Freika/dawarich/blob/1.19.0/lib/oidc_config.rb) | faible | oui ; traceurs par clé d'API |
| Karakeep 0.34.1 | natif ; appli et extension : mot de passe ou clé d'API | [auth.ts](https://github.com/karakeep-app/karakeep/blob/v0.34.1/apps/web/server/auth.ts) | faible | **obligatoire** pour les clients |
| Beszel 0.21.1 | OAuth2 PocketBase, liaison par e-mail | [doc](https://beszel.dev/guide/oauth) (latest) | faible | oui ; secret client saisi dans l'UI du hub, hors Ansible ; superuser Homepage à part |
| Immich Swipe (`sha-a9644ff`) | aucun : clé d'API Immich saisie dans le navigateur (à confirmer) | — | — | **reste tel quel** : le mur Pangolin, puis la clé d'API |
| Stirling-PDF 3.2.2 | gratuit depuis 3.0 | [v3.0.0](https://github.com/Stirling-Tools/Stirling-PDF/releases/tag/v3.0.0) | — | rien à faire : pas de login, le mur suffit |
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
