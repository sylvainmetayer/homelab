# 0016. Login unifié : Authelia comme fournisseur OIDC, de Pangolin et des applis

- **Statut** : proposée
- **Date** : 2026-10-29

Dépasse les 40 lignes du modèle, à dessein : le comparatif des IdP est gardé ici.

## Contexte

On se connecte deux fois : le mur SSO de Pangolin (comptes internes), puis le
compte local de l'appli. Pangolin `ee-1.25.3` délègue son login à un IdP OIDC
([doc](https://docs.pangolin.net/manage/identity-providers/add-an-idp)), que le
provider 1.6.1 déclare (`pangolin_idp`, `pangolin_idp_org`, `role_mapping`).
Plusieurs rôles par utilisateur exigent une clé EE (gratuite en usage perso) ;
compte interne jamais relié à l'IdP, rôles réécrits à chaque login.
Support par appli : [login-unifie-applis.md](../login-unifie-applis.md).

Exigence ajoutée : passkeys **et** un login classique mot de passe + TOTP (ou
clé WebAuthn en second facteur) pour un appareil sans passkey, un second
utilisateur, la récupération. L'IdP ne peut pas être derrière le mur qu'il
sert ; place : VM Pangolin (CX23, 2 vCPU / 4 Gio partagés avec Pangolin,
Traefik, CrowdSec) ; SQLite ou petit Postgres, sauvegardé par borgmatic.

## Comparatif (relevé le 2026-10-29)

Sécurité : GHSA publiées sur le dépôt depuis le 2025-01-01 (dont high/critical) ;
un projet qui publie ses CVE ailleurs est sous-compté. RAM : annoncée, à mesurer.

| IdP (version) | Mot de passe + TOTP | WebAuthn 2ᵉ facteur | Passkey seul | OIDC : groupes, PKCE, refresh, groupes par client | Reset / SMTP | RAM, stockage | Admin | Tofu | Sécurité 2025-26 | Santé | Pangolin |
|---|---|---|---|---|---|---|---|---|---|---|---|
| [Pocket ID](https://pocket-id.org/docs/guides/sign-in-methods) v2.19.1 | **non**, par conception ([#937](https://github.com/pocket-id/pocket-id/issues/937) « not planned ») | — | oui | oui, oui, oui, oui (allowed groups) | codes de login par e-mail (SMTP) ou par l'admin ; QR depuis un autre appareil | ~30 Mio (à confirmer), SQLite ou Postgres | UI | communautaire `trozz/pocketid` | 17 (6) | 28 versions en 12 mois | [guide officiel](https://docs.pangolin.net/manage/identity-providers/pocket-id) |
| [Authelia](https://www.authelia.com/configuration/second-factor/webauthn/) v4.39.28 | oui | oui | oui depuis 4.39 (`enable_passkey_login`), compte un facteur : mot de passe demandé ensuite en `two_factor` | oui, oui, oui, oui (`authorization_policy` par client) ; [OpenID Certified](https://www.authelia.com/blog/we-are-now-openid-certified/) (5 profils) | reset et changement de mot de passe, enrôlement TOTP/WebAuthn vérifié par e-mail (SMTP) | ~30 Mio (à confirmer), SQLite ou Postgres | fichier YAML, pas d'UI admin | aucun (config Ansible) | 4 (0) | 15 versions en 12 mois (correctifs 4.39), 3 mainteneurs bénévoles | [guide Authelia](https://www.authelia.com/integration/openid-connect/clients/pangolin/) |
| LLDAP v0.6.3 + Authelia | oui (Authelia) | oui | oui | comme Authelia, groupes gérés dans LLDAP | reset en libre-service par LLDAP ou Authelia (SMTP) | + ~10 Mio (à confirmer), SQLite | UI LLDAP | communautaire `tasansga/lldap` | 0 (0) LLDAP | LLDAP : 2 versions en 15 mois | comme Authelia |
| [VoidAuth](https://github.com/voidauth/voidauth) v1.17.1 | oui | oui | oui (comptes passkey seul) | oui, oui, oui, oui ; MFA exigible par appli ou groupe | reset par e-mail (SMTP), invitations | Node, ~100 Mio (à confirmer), SQLite ou Postgres | UI | communautaire, inutilisé | 5 (3) dont 1 critical (2026-09) | né en 2025-04, un mainteneur quasi seul | guide VoidAuth |
| [Rauthy](https://github.com/sebadob/rauthy) v0.37.2 | **pas de TOTP** (à confirmer) | oui | oui (UV exigé) | oui, oui, oui, à confirmer | e-mail (SMTP) | ~40 Mio annoncés, Hiqlite (SQLite + Raft) ou Postgres | UI | aucun | 3 (1) | un mainteneur principal, versions mensuelles | OIDC générique |
| [Kanidm](https://kanidm.github.io/kanidm/stable/accounts/authentication_and_credentials.html) v1.11.2 | oui | oui (passkey) | oui | oui, imposé, oui, oui (scope maps) | **pas d'e-mail** : jeton de reset donné par l'admin | ~50 Mio (à confirmer), base intégrée ; TLS imposé même derrière Traefik | CLI surtout | communautaires, inutilisés | 10 (4) | versions trimestrielles | OIDC générique |
| Tinyauth v5.2.0 | oui (utilisateurs en variables, TOTP) | **non** | **non** | oui (certifié Basic OP), à confirmer pour le reste | non | ~20 Mio (à confirmer), SQLite | fichier | aucun | 9 (6) | un mainteneur | OIDC générique |
| Casdoor v4.24.0 | oui | oui | oui | oui, oui, oui, oui | e-mail/SMS (SMTP) | Go ~100 Mio (à confirmer), SQLite/MySQL/Postgres | UI | communautaire, inutilisé | 0 GHSA, CVE publiées ailleurs (à confirmer) | versions hebdomadaires, éditeur Casbin | OIDC générique |
| Logto v1.45.0 | oui (+ codes e-mail/SMS) | oui | oui depuis 1.38 | oui, oui, oui, à confirmer | e-mail (SMTP) | Node + **Postgres** obligatoire, ~300 Mio (à confirmer) | UI | aucun | 13 (10) | éditeur (Silverhand), mensuel | OIDC générique |
| Zitadel v4.20.0 | oui (+ OTP e-mail/SMS) | oui | oui | oui (rôles de projet), oui, oui, oui | e-mail (SMTP) | **Postgres** obligatoire, ~500 Mio (à confirmer) | UI | officiel `zitadel/zitadel` | 58 (41) | éditeur, hebdomadaire | [guide officiel](https://docs.pangolin.net/manage/identity-providers/zitadel) |
| Authentik 2026.8.5 | oui | oui | oui (flux) | oui, oui, oui, oui (bindings) | e-mail (SMTP) | **Postgres** + serveur + worker, ≥ 2 Gio d'hôte (à confirmer) | UI | officiel `goauthentik/authentik` | 29 (22) | éditeur, mensuel | OIDC générique |
| Keycloak 26.8.1 | oui | oui | oui (26.4+, à confirmer) | oui, oui, oui, oui | e-mail (SMTP) | JVM ~1,3 Gio + **Postgres** | UI | officiel `keycloak/keycloak` (mûr) | 33 (14) | Red Hat / CNCF, mensuel | OIDC générique ; déjà connu (banc Flip) |

Sources des versions, GHSA et dates : API GitHub de chaque dépôt et registre
OpenTofu, relevés le 2026-10-29.

## Shortlist notée

Sur 5 : méthodes de login voulues / poids sur la VM Pangolin / code (Ansible,
Tofu) / sécurité et santé / Pangolin / confort (UI, libre-service).

| IdP | Login | Poids | Code | Sécurité | Pangolin | Confort | Total /30 |
|---|---|---|---|---|---|---|---|
| **Authelia** (fichier d'utilisateurs) | 5 | 5 | 4 | 5 | 4 | 2 | **25** |
| Authelia + LLDAP | 5 | 4 | 3 | 4 | 4 | 4 | 24 |
| Pocket ID | 2 | 5 | 3 | 2 | 5 | 5 | 22 |
| VoidAuth | 5 | 4 | 2 | 1 | 4 | 5 | 21 |
| Kanidm | 4 | 4 | 2 | 3 | 3 | 2 | 18 |
| Keycloak | 5 | 1 | 5 | 3 | 3 | 4 | 21, mais hors VM Pangolin |

## Décision

- **Authelia 4.39** sur la **VM Pangolin**, `id.sylvain.cloud` par un routeur
  Traefik du rôle `pangolin` (le mur ne peut pas le protéger) : ni filtre FR/DE
  ([0002](0002-pangolin-seule-entree-publique.md)) ni moniteur généré,
  exception assumée, moniteur déclaré à part ; SQLite sauvegardée par
  `sqlite3 .backup` dans le borgmatic de Pangolin ; pas d'automerge Renovate.
- Facteurs : passkey (`enable_passkey_login`) puis mot de passe, ou mot de
  passe + TOTP ou clé WebAuthn ; tous les clients en `two_factor`. Le mode
  passkey seul (`experimental_enable_passkey_uv_two_factors`) n'est pas
  supporté par Authelia : pas activé.
- Utilisateurs dans le fichier YAML (deux comptes), hachés depuis SOPS et
  rendus par Ansible ; clients OIDC dans la config Ansible, pas de provider
  Tofu (aucun n'existe) ; côté Pangolin, `pangolin_idp` reste en Tofu.
  Reset et changement de mot de passe dans l'UI désactivés : Ansible
  écraserait le fichier. SMTP Infomaniak pour le code qui vérifie l'identité
  à l'enrôlement d'un TOTP ou d'une clé.
- Groupes dans l'ID token par une `claims_policy` (Authelia 4.39 ne les y met
  plus par défaut ; « claims hydration » de son guide Pangolin).
- Mur Pangolin délégué, groupes → rôles par appli **plus** `jellyfin` et
  `Admin` ; un admin interne gardé en secours ; comptes Flip internes.
- Applis : OIDC natif là où le **login local reste en secours** ; pilote
  **Homebox** (inscription fermée de [0014](0014-homebox.md) à concilier) ;
  BookStack et FreshRSS (OIDC exclusif) en dernier ; chemins des clients
  mobiles inchangés.

## Alternatives écartées

- **Pocket ID** : passkeys seuls par conception, TOTP refusé (#937) ; le
  repli est un code de login par e-mail, donc la boîte mail ouvre tout ;
  17 GHSA depuis 2025, dont 6 high/critical (refresh token contournant les
  groupes, CSRF créant un admin). Reste le plus simple si l'exigence tombe.
- **VoidAuth** : coche tout, mais un mainteneur, dix-huit mois d'âge et une
  faille critical en 2026-09. À revoir dans un an.
- **LLDAP** devant Authelia : à ajouter si un second utilisateur doit gérer
  son mot de passe seul ; un service de plus pour deux comptes aujourd'hui.
- **Kanidm** : pas de reset par e-mail, TLS imposé, réglage en CLI.
  **Rauthy** : pas de TOTP (à confirmer), un mainteneur. **Tinyauth** : ni
  passkey ni WebAuthn.
- **Keycloak** (~1,3 Gio), **Authentik**, **Zitadel**, **Logto** : Postgres et
  trop lourds pour la VM Pangolin ; sur la VM docker, l'IdP serait derrière
  Pangolin et sa panne fermerait le mur. **Casdoor** : CVE non publiées sur son
  dépôt (à confirmer), éditeur peu transparent.

## Conséquences

- Un passkey ou mot de passe + TOTP ouvre tout ; panne d'Authelia : admin
  interne Pangolin et logins locaux.
- Pas d'UI d'admin : un compte ou un client de plus passe par une PR, comme le
  reste du homelab ; un mot de passe oublié se refait par Ansible.
- Comptes Pangolin à recréer ; secrets clients en SOPS (hachés pbkdf2 dans la
  config) sauf Wishlist et Beszel (saisis dans l'UI) ; RAM et clé EE à vérifier
  d'abord.

## Liens

- [Authelia : passkeys](https://www.authelia.com/configuration/second-factor/webauthn/),
  [notes 4.39](https://github.com/authelia/authelia/blob/master/docs/content/blog/release-notes-4.39/index.md),
  [client Pangolin](https://www.authelia.com/integration/openid-connect/clients/pangolin/)
- [Pocket ID : méthodes de connexion](https://pocket-id.org/docs/guides/sign-in-methods),
  [#937](https://github.com/pocket-id/pocket-id/issues/937)
- [VoidAuth : MFA et groupes](https://github.com/voidauth/voidauth/tree/main/docs)
- [Pangolin : IdP](https://docs.pangolin.net/manage/identity-providers/add-an-idp),
  [login-unifie-applis.md](../login-unifie-applis.md)
