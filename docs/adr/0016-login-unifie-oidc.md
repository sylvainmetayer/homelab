# 0016. Login unifié : Pocket ID comme fournisseur OIDC, de Pangolin et des applis

- **Statut** : proposée
- **Date** : 2026-10-29

## Contexte

On se connecte deux fois : le mur SSO de Pangolin (comptes internes), puis le
compte local de l'appli. Pangolin `ee-1.25.3` délègue son login à un IdP OIDC
([doc](https://docs.pangolin.net/manage/identity-providers/add-an-idp)), que le
provider 1.6.1 déclare (`pangolin_idp`, `pangolin_idp_org`, `role_mapping`).
Plusieurs rôles par utilisateur exigent une clé EE (gratuite en usage perso) ;
compte interne jamais relié à l'IdP, rôles réécrits à chaque login.
Support par appli : [login-unifie-applis.md](../login-unifie-applis.md).

## Décision

- **Pocket ID** (passkeys seuls, SQLite, « allowed groups » par client) sur la
  **VM Pangolin**, `id.sylvain.cloud` par un routeur Traefik du rôle `pangolin`
  (le mur ne peut pas le protéger) : ni filtre FR/DE ([0002](0002-pangolin-seule-entree-publique.md))
  ni moniteur généré, exception assumée, moniteur déclaré à part ; sauvegarde
  `sqlite3 .backup` dans le borgmatic de Pangolin ; pas d'automerge Renovate.
- Mur Pangolin délégué, groupes → rôles par appli **plus** `jellyfin` et
  `Admin` ; un admin interne gardé en secours ; comptes Flip internes.
- Applis : OIDC natif là où le **login local reste en secours** ; pilote
  **Homebox** (inscription fermée de [0014](0014-homebox.md) à concilier) ;
  BookStack et FreshRSS (OIDC exclusif) en dernier ; chemins des clients
  mobiles inchangés.

## Alternatives écartées

- **Keycloak** (~1,3 Gio + Postgres), **Authentik**, **Zitadel** : lourds.
  **Authelia** : possible aussi comme fournisseur OIDC, moins simple pour les
  passkeys seuls (à confirmer). **Kanidm** : TLS imposé, réglage en CLI.

## Conséquences

- Un passkey ouvre tout ; panne de Pocket ID : admin interne et logins locaux.
  Comptes Pangolin à recréer ; secrets clients en SOPS sauf Wishlist et Beszel
  (saisis dans l'UI) ; RAM et clé EE à vérifier d'abord.
