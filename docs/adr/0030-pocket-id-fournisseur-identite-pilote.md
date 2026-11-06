# 0030. Pocket ID, fournisseur d'identité en pilote, public hors du filtre FR/DE

- **Statut** : acceptée (pilote) ; remplace [0016](0016-login-unifie-oidc.md) ; exception à [0002](0002-pangolin-seule-entree-publique.md)
- **Date** : 2026-11-05

## Contexte

Le 05/11, Sylvain choisit d'essayer **Pocket ID** (v2.19.1, passkeys seuls) à la
place d'Authelia, prévu par 0016 (jamais mis en œuvre). Le comparatif de 0016
reste valable. Le pilote ne concerne **que son compte** : le foyer ne change
rien, les comptes internes de Pangolin restent le secours. Pocket ID n'a ni mot
de passe ni TOTP, par conception ([#937](https://github.com/pocket-id/pocket-id/issues/937)) :
d'où deux passkeys au moins, et un code créé par l'administrateur en secours.

## Décision

- **`id.sylvain.cloud` sur la VM Pangolin**, par un routeur Traefik du rôle
  `pangolin` (jamais une ressource Pangolin : derrière le mur SSO qu'il sert,
  personne ne pourrait s'y connecter). **Exception à 0002** : service public,
  **hors filtre FR/DE** (un passkey se présente de n'importe où), sans SSO ;
  seuls le débit par IP, CrowdSec et les en-têtes de l'entrypoint s'appliquent.
- Rôle `pocket_id` : image par digest (v2.19.1 : la 2.19.2 a 2,5 jours le
  05/11, Renovate attend 3), sans privilège, `read_only`, `cap_drop: ALL`,
  `mem_limit` 256m, SQLite sauvegardée par le gabarit borgmatic, moniteurs Kuma,
  entrée du test de restauration, **hors automerge Renovate**. Rendu seulement si
  la clé SOPS `pocket_id_encryption_key` existe.
- Pangolin : `pangolin_idp` en Tofu (le fork le gère), **auto-provision coupée**,
  rôle `Member` (levé le 2026-11-06, voir « Évolution » plus bas) ; aucun compte interne déclaré ni relié. Applis : **Homebox
  seul**, login local gardé.
- **Risques** : 17 avis de sécurité publiés depuis 2025-01-01, dont 6 high ou
  critical : e-mail vérifié usurpable (critical, 2026-07), CSRF créant un
  administrateur (2026-08), jetons de rafraîchissement contournant la
  révocation et les groupes (2026-04), `redirect_uri` et codes d'autorisation
  inter-clients (2026-03), audiences arbitraires (2026-07). Un IdP compromis
  vaut une connexion à tout ce qui lui fait confiance : d'où le pilote étroit,
  et la page `/setup` (premier administrateur, avis de concurrence 2026-07)
  réservée à `home_ip` tant que le compte n'existe pas.
- **Retour arrière** : retirer de `tofu/pangolin_config/pocket_id.tf` les
  clients, le groupe, `pangolin_idp` et le provider `pocketid`, `tofu apply`
  tant que Pocket ID répond (sinon `tofu state rm` des ressources `pocketid_*`),
  retirer les clés SOPS puis `pangolin.yaml --tags pangolin,pocket_id` (routeur
  retiré ; le conteneur se supprime à la main, les données restent), rien d'autre
  ne dépend de lui. Authelia reste possible : 0016 reste lisible.

## Alternatives écartées

- **Authelia** (0016) : pas d'interface d'administration ni de passkey seul ;
  l'essai de Pocket ID tranche sur l'usage, pas sur le comparatif.
- **Derrière le SSO de Pangolin** : impossible, c'est lui le fournisseur.
- **Sur la VM docker** : sa panne fermerait aussi le mur des applis du Pi et de flip.

## Conséquences

- Une ouverture publique de plus, hors pays : sa surface est celle de Pocket ID.
- Panne de l'IdP : mur Pangolin et logins locaux intacts (le pilote n'y touche pas).
  Mais `tofu plan` de `pangolin_config` échoue en lisant les clients OIDC : le
  reste se planifie avec `-exclude` sur les ressources `pocketid_*`.
- Perte de tous les passkeys : code à usage unique créé sur l'hôte
  ([runbook](../runbooks/pocket-id.md)). Premier démarrage non testé en CI.

## Évolution du 2026-11-06 : rôles Pangolin repris des groupes Pocket ID

Donner une appli demandait deux gestes (groupe Pocket ID, rôle Pangolin). Désormais
`auto_provision = true` et la règle de rôles rend les groupes Pocket ID dont le
nom est un rôle d'appli ; un groupe Pocket ID par rôle Pangolin, déclaré en Tofu.
Écartés : retirer le mur des applis branchées (pages de login exposées), un rôle
unique pour tout le foyer (les applis sans OIDC perdaient leur filtre), tout
déclarer en Tofu (utilisateurs Pocket ID et noms du foyer dans le dépôt public).
Dépend de la licence Enterprise : sans elle, un seul rôle par personne (des
accès en moins, jamais en trop). Comptes internes inchangés.

## Liens

[runbook](../runbooks/pocket-id.md), `ansible/roles/pocket_id/README.md`,
`tofu/pangolin_config/pocket_id.tf`, [login-unifie-applis.md](../login-unifie-applis.md),
[Pangolin : Pocket ID](https://docs.pangolin.net/manage/identity-providers/pocket-id),
[Pocket ID : mise à jour](https://pocket-id.org/docs/setup/upgrading).
