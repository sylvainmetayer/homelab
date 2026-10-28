# 0004. Nextcloud derrière le SSO Pangolin, clients ouverts par chemin

- **Statut** : acceptée
- **Date** : 2026-10-28

## Contexte

Nextcloud était public sans SSO (`sso = false`) : sa page de connexion et
tout son PHP répondaient au monde (FR/DE). Les clients (bureau, Android,
DAVx5, Thunderbird) ne savent pas passer le SSO de Pangolin.

## Décision

- `website_nextcloud.tf` : `sso = true`, rôle `nextcloud`.
- Chemins ACCEPT (priorité 4, `local.path_bypasses`) pour les clients
  (`status.php`, `remote.php/*`, OCS, Login Flow v2 init/poll…) et les
  partages publics (`/s/*`, `public.php/*`, assets). La page de connexion,
  les réglages, `/core/*` et tout segment `ajax` restent derrière le SSO.
- **Mots de passe d'application obligatoires** : `token_auth_enforced`
  (`nextcloud_token_auth_enforced: true`) ; un mot de passe de connexion ne
  marche plus sur DAV/OCS.
- `trusted_proxies` = réseau `newt` : la vraie IP du client au bruteforce.

## Alternatives écartées

- **Rester sans SSO** : toute faille de PHP exposée (le verrouillage PHP du
  2026-10-21, `php_lockdown.tf`, a dû le forcer en urgence).
- **Tout Nextcloud derrière le SSO** : plus aucun client ne synchronise.

## Conséquences

- Avant le merge, chaque client a dû passer à un mot de passe d'application
  (audit : `docs/runbooks/nextcloud-app-passwords.sh`).
- Non ouverts : Login Flow v1, Notes, Deck, liens publics d'Agenda, Forms,
  Talk. OCS l'est en entier : un mot de passe d'application admin y suffit.

## Liens

PR #701, #917 (runbook et script d'audit), #918 (correctif du script) ;
[runbooks/nextcloud-mots-de-passe-application.md](../runbooks/nextcloud-mots-de-passe-application.md).
