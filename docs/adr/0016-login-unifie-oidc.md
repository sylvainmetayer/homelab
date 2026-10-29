# 0016. Login unifié : Pocket ID comme fournisseur OIDC, de Pangolin et des applis

- **Statut** : proposée
- **Date** : 2026-10-29

## Contexte

On se connecte deux fois : le mur SSO de Pangolin (comptes internes, faits
dans l'UI), puis le compte local de l'appli. Pangolin `ee-1.25.3` sait déléguer
son login à un IdP OIDC (session unique pour le tableau de bord et le mur,
[doc](https://docs.pangolin.net/manage/identity-providers/add-an-idp)), et le
provider `stackopshq/pangolin` 1.6.1 le déclare (`pangolin_idp`,
`pangolin_idp_org` avec `role_mapping` JMESPath,
[docs](https://github.com/stackopshq/terraform-provider-pangolin/tree/v1.6.1/docs/resources)).
Plusieurs rôles par utilisateur (un `pangolin_role` par appli ici) exigent une
clé EE activée, gratuite pour un usage personnel : sans elle, seul le premier
rôle mappé est gardé
([`validateOidcCallback.ts`](https://github.com/fosrl/pangolin/blob/1.25.3/server/routers/idp/validateOidcCallback.ts),
[licence](https://docs.pangolin.net/self-host/enterprise-edition/personal-use)).
Un utilisateur interne n'est jamais relié à un utilisateur IdP (recherche sur
`username` **et** `idpId`), et les rôles sont réécrits à chaque login.

## Décision

- **Pocket ID** ([pocket-id.org](https://pocket-id.org/docs/introduction)) :
  passkeys seulement, SQLite, groupes et « allowed groups » par client,
  guide Pangolin officiel, provider Tofu `trozz/pocketid`.
- Sur la **VM Pangolin**, `id.sylvain.cloud` servi par un routeur Traefik du
  rôle `pangolin` comme le tableau de bord (CrowdSec s'applique) : même domaine
  de panne que le mur, qui ne peut pas être derrière lui. SQLite sur disque
  local, `sqlite3 .backup` dans le borgmatic de Pangolin, `ENCRYPTION_KEY` en
  SOPS. Pas d'automerge Renovate (17 avis de sécurité en 2026).
- Pangolin : `pangolin_idp` + `pangolin_idp_org`, groupes Pocket ID → rôles
  par appli, auto-provisionnement ; **un compte interne admin gardé** en secours.
- Applis : OIDC natif là où il garde le **login local en secours** ; les
  clients mobiles et ouvertures de chemins de [acces-mobile.md](../acces-mobile.md)
  ne changent pas.

| Appli (version) | OIDC | Source | Effort | Login local gardé |
|---|---|---|---|---|
| Homebox 0.27.1 (pilote) | natif, liaison par e-mail | [conf.go](https://github.com/sysadminsmedia/homebox/blob/v0.27.1/backend/internal/sys/config/conf.go) | faible | oui (`ALLOW_LOCAL_LOGIN`) ; chaque nouveau compte a son propre foyer |
| Immich v3.3.5 | natif, rôle et quota par claim, appli mobile OK | [doc](https://docs.immich.app/administration/oauth) | faible | oui (`passwordLogin`) |
| Nextcloud 35.0.2 | `user_oidc` 8.11.0, groupes | [README](https://github.com/nextcloud/user_oidc/blob/v8.11.0/README.md) | moyen (uid à aligner) | oui (`/login?direct=1`) ; clients par login flow v2 non confirmé |
| TREK 5.0.0 | natif, admin par claim | [oidc.service.ts](https://github.com/liketrek/TREK/blob/v5.0.0/server/src/nest/oidc/oidc.service.ts) | faible | oui sauf `OIDC_ONLY` |
| Wishlist v0.69.0 | natif, réglé dans l'UI | [config.ts](https://github.com/cmintey/wishlist/blob/v0.69.0/src/lib/server/config.ts) | faible | oui |
| Meerkat CRM 1.7.0 | natif | [oidc_service.go](https://github.com/fbuchner/meerkat-crm/blob/v1.7.0/backend/services/oidc_service.go) | faible | **obligatoire** : CardDAV en Basic sur le mot de passe local |
| Dawarich 1.19.0 | natif, liaison par défi | [oidc_config.rb](https://github.com/Freika/dawarich/blob/1.19.0/lib/oidc_config.rb) | faible | oui ; traceurs par clé d'API |
| KitchenOwl v0.7.10 | natif, appli mobile OK | [doc](https://docs.kitchenowl.org/latest/self-hosting/oidc/) | moyen | oui ; tout login OIDC crée un compte : allowed groups obligatoires |
| Karakeep 0.34.1 | natif ; appli et extension : mot de passe ou clé d'API | [auth.ts](https://github.com/karakeep-app/karakeep/blob/v0.34.1/apps/web/server/auth.ts) | faible | **obligatoire** pour les clients |
| Beszel 0.21.1 | OAuth2 PocketBase, liaison par e-mail | [doc](https://beszel.dev/guide/oauth) (latest) | faible | oui ; superuser Homepage à part |
| Stirling-PDF 3.2.2 | gratuit depuis 3.0 | [v3.0.0](https://github.com/Stirling-Tools/Stirling-PDF/releases/tag/v3.0.0) | — | rien à faire : pas de login, le mur suffit |
| Homepage v2.7.0 | porte OIDC sans rôles | [doc](https://github.com/gethomepage/homepage/blob/v2.7.0/docs/installation/index.md) | — | rien à faire : le mur suffit |
| BookStack 26.09 | `AUTH_METHOD=oidc`, **exclusif**, liaison par `external_auth_id` | [doc](https://www.bookstackapp.com/docs/admin/oidc-auth/) | moyen | **non** : en dernier |
| FreshRSS 1.30.4 | `mod_auth_openidc`, **exclusif** (`http_auth`) | [doc](https://freshrss.github.io/FreshRSS/en/admins/16_OpenID-Connect.html) | moyen | **non** ; API mobile hors OIDC |
| vmauth v1.155.0 | SSO OIDC open source depuis 1.153 | [vmauth.md](https://github.com/VictoriaMetrics/VictoriaMetrics/blob/v1.155.0/docs/victoriametrics/vmauth.md) | moyen | à tester : `jwt` mêlé aux comptes Basic des agents non confirmé |
| Paperless-ngx 3.3 | allauth OIDC, groupes | [configuration.md](https://github.com/paperless-ngx/paperless-ngx/blob/v3.3.4/docs/configuration.md) | — | en pause : à la reprise |
| Jellyfin 12.4 | plugin communautaire (fork K0lin), Quick Connect pour les TV | [v5.1.0](https://github.com/K0lin/jellyfin-plugin-sso/releases/tag/v5.1.0) | — | **reste tel quel** |
| Monica 3.7.0, Speedtest Tracker 1.15.1, ntfy v2.34.0, Uptime Kuma 2.5.8 | aucun ([ntfy #1596](https://github.com/binwiederhier/ntfy/issues/1596), [Kuma #6539](https://github.com/louislam/uptime-kuma/issues/6539)) | code aux tags | — | **reste tel quel** : le mur Pangolin, puis leur compte |
| Flip Planning, Betisier, Promptoramix | Keycloak à soi / public | — | — | **reste tel quel** : autres utilisateurs |

**Ordre** : vérifier la clé EE ; Pocket ID et passkeys ; **pilote Homebox** ;
mur Pangolin (comptes recréés côté IdP) ; Immich, TREK, Wishlist, Dawarich,
Meerkat, Beszel, Nextcloud, KitchenOwl, Karakeep ; BookStack, FreshRSS, vmauth
en dernier, si le gain vaut le login local perdu.

## Alternatives écartées

- **Keycloak** : mûr, le meilleur provider Tofu, mais ~1,3 Gio
  ([dimensionnement](https://www.keycloak.org/high-availability/multi-cluster/concepts-memory-and-cpu-sizing))
  plus Postgres ; celui de Flip est le realm de l'appli (image maison, en pause).
- **Authelia** : portail forward-auth qui double le mur, pas de logout RP.
- **Authentik, Zitadel** : Postgres, ≥ 2 Gio pour Authentik, bilans d'avis 2026
  les plus lourds. **Kanidm** : TLS imposé sur le serveur, réglage en CLI.
- **IdP sur la VM docker derrière une ressource `sso = false`** : sa panne
  fermerait le mur des applis du Pi et de flip.
- **En-têtes `Remote-*` de Pangolin** ([doc](https://docs.pangolin.net/manage/access-control/forwarded-headers)) :
  peu d'applis s'y fient, et tout conteneur du réseau `newt` pourrait les forger.

## Conséquences

- Un passkey ouvre le mur et, par la session Pocket ID, les applis OIDC.
- Pocket ID en panne : plus de mur que par le compte interne de secours, plus
  d'appli que par son login local. Comptes Pangolin à recréer (pas de liaison).
- Un secret client par appli (SOPS, `secrets-rotation.yaml`) ; `skip_to_idp_id`
  dans `local.resource_pins` s'il est utilisé ; RAM de Pocket ID non mesurée.

## Liens

[0002](0002-pangolin-seule-entree-publique.md), [0004](0004-nextcloud-derriere-le-sso.md),
[acces-mobile.md](../acces-mobile.md), `tofu/pangolin_config/roles.tf`,
[guide Pocket ID](https://docs.pangolin.net/manage/identity-providers/pocket-id).
