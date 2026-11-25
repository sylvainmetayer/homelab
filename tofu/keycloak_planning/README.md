# tofu/keycloak_planning

Realm `planning` du Keycloak de **production** de Flip Planning : conteneurs
`flip-planning-keycloak` et `flip-planning-keycloak-db` de la pile
`flip_planning` sur flip (rôle `flip_planning`, `flip_planning_keycloak_enabled`),
servi sous `/auth` de `flip-planning.sylvain.cloud`.

Émetteur (issuer) : **`https://flip-planning.sylvain.cloud/auth/realms/planning`**.
L'application lie chaque compte au couple émetteur + sujet : le changer impose
la procédure « Changer l'URL du fournisseur » de `docs/oidc.md` du dépôt
planning-equipes. But : répéter le chemin d'un futur client (comptes Keycloak
aujourd'hui, fédération de son annuaire demain, bascule sur son ADFS ensuite).

## Ce que fait le module

- Le realm (pas d'inscription libre, connexion par adresse, anti-force brute,
  politique de mot de passe, événements gardés 7 jours, pas de SMTP).
- Le client `planning-app` : confidentiel, code + PKCE S256, redirections
  **exactes** `/api/auth/oidc/login` et `/login`, secret lu dans SOPS
  (`prod_planning_oidc_client_secret`, le même que l'`OIDC_CLIENT_SECRET` de
  l'application, ≥ 32 caractères).
- L'audience MCP : client `planning-mcp` (n'émet rien), scope
  `planning-mcp-audience` et son mappeur, posé dans les scopes par défaut du
  realm pour que les clients MCP enregistrés ensuite l'aient.
- L'enregistrement dynamique des clients MCP, fermé par défaut (plus bas).

Le provider passe par Internet : l'API d'administration et le realm master sont
derrière le SSO Pangolin de Flip Planning (seuls `/auth/realms/planning/*` et
`/auth/resources/*` en sont sortis, `tofu/pangolin_config/website_flip_planning.tf`).
Il présente le jeton d'accès de la ressource (sortie `flip_planning_access_token`
de `tofu/pangolin_config`, lue par `terraform_remote_state`), puis le bootstrap
admin (`prod_planning_keycloak_admin_password`).

Les personnes ne sont pas dans Tofu.

## Mise en route (Sylvain, dans cet ordre)

1. **Secrets** (dépôt `homelab-secrets`, puis bump du sous-module ici), avec
   leurs entrées dans `secrets/secrets-rotation.yaml` :
   `prod_planning_keycloak_db_password`, `prod_planning_keycloak_admin_password`,
   `prod_planning_oidc_client_secret` (48 caractères alphanumériques, par ex.
   `openssl rand -hex 24`).
2. **Déploiement** : `ansible-playbook flip.yml --tags flip_planning` (ou un
   `workflow_dispatch` du déploiement). Keycloak démarre (premier démarrage :
   une à deux minutes, il construit sa configuration) ; l'application ne change
   pas (`flip_planning_oidc_enabled: false`).
3. **Pangolin** : `tofu apply` de `tofu/pangolin_config` (cible `/auth`, chemins
   ouverts) — skill `pangolin-config-plan`. Vérifier :
   `curl -s https://flip-planning.sylvain.cloud/auth/realms/planning/.well-known/openid-configuration`
   répond du JSON hors SSO, et `/auth/admin/` tombe sur le mur Pangolin.
4. **Realm** : `mise exec -- tofu -chdir=tofu/keycloak_planning init`, `plan`, `apply`.
5. **Comptes** : console `https://flip-planning.sylvain.cloud/auth/admin/master/console/`
   (derrière le mur Pangolin), realm `planning` › Users : adresse, **Email
   verified** coché (l'application ne rattache que sur une adresse vérifiée),
   mot de passe temporaire. Remplacer le bootstrap admin du master par un
   compte permanent (Keycloak le demande).
6. **Dans l'application, AVANT de brancher OIDC** : créer son propre compte
   administrateur (Paramètres › Comptes, la même adresse que dans Keycloak).
   Le compte `admin` de secours se ferme derrière un fournisseur.
7. **Brancher l'application** : `flip_planning_oidc_enabled: true` dans
   l'entrée prod de `ansible/flip.yml`, PR, déploiement. Le rôle écrit
   `OIDC_ENABLED=true`, `OIDC_AUTH_SERVER_URL` (l'émetteur ci-dessus),
   `OIDC_CLIENT_ID=planning-app`, `OIDC_CLIENT_SECRET`, `OIDC_FORCE_HTTPS=true`,
   `OIDC_MCP_AUDIENCE=planning-mcp`, `ADMIN_LOCAL_SECOURS=false`.

Retour arrière : `flip_planning_oidc_enabled: false` (les comptes locaux et le
secours reviennent) ; Keycloak se retire en ôtant ses deux secrets de SOPS puis
`docker compose rm` de ses conteneurs.

## Enregistrement dynamique (clients MCP hébergés)

Claude sur le web et Le Chat enregistrent leur client eux-mêmes, sans jeton,
depuis leurs serveurs. Keycloak crée avec le realm des politiques « anonymous »
dont **Trusted Hosts à liste vide**, qui refuse tout : c'est l'état par défaut ici.

Réglage proposé, pour ouvrir (`dcr_trusted_hosts`, dans un `terraform.tfvars`
non versionné ou en défaut de la variable) :

```hcl
dcr_trusted_hosts = ["claude.ai", "claude.com", "chat.mistral.ai"]
```

- seuls les clients dont **toutes** les URI de redirection sont sur ces hôtes
  passent (`client-uris-must-match`), d'où qu'ils appellent (les serveurs des
  assistants n'ont pas d'adresse stable : `host-sending-registration-request-must-match`
  faux) ; un code ne repart donc que chez l'assistant ;
- 20 clients au plus (au lieu de 200) ;
- gardées telles que Keycloak les pose : écran de consentement, scopes par
  défaut seulement, types de mappeurs limités, Full Scope Disabled ;
- un client enregistré n'ouvre rien seul : il faut une personne qui se
  connecte au realm ET un compte actif avec un droit dans l'application
  (`docs/mcp.md`).

Les deux politiques existent déjà (vérifié sur un Keycloak 26.8.2 neuf :
« Trusted Hosts » et « Max Clients Limit », sous-type anonymous) : Tofu doit les
**prendre en main** avant l'apply, sinon il en crée une seconde et la liste
vide de la première refuse toujours. Identifiants dans la console (realm
`planning` › Clients › Client registration › Anonymous access policies, l'id
est dans l'URL de la politique), puis (pas de bloc `import` : il fait paniquer
`tofu test`) :

```bash
mise exec -- tofu -chdir=tofu/keycloak_planning import -var 'dcr_trusted_hosts=["claude.ai"]' \
  'keycloak_realm_client_registration_policy.trusted_hosts[0]' 'planning/<id Trusted Hosts>'
mise exec -- tofu -chdir=tofu/keycloak_planning import -var 'dcr_trusted_hosts=["claude.ai"]' \
  'keycloak_realm_client_registration_policy.max_clients[0]' 'planning/<id Max Clients Limit>'
```

Format `realm/id` à confirmer contre la doc du provider au premier import ; le
plan qui suit doit montrer des mises à jour en place, jamais une création. Les
chemins Pangolin couvrent déjà l'endpoint
`/auth/realms/planning/clients-registrations/openid-connect`.

## Mémoire

Mesuré le 25/11/2026 sur flip (3,8 Gio, 2 vCPU) : ~2,0 Gio disponibles au
repos ; l'application monte d'environ 0,9 Gio pendant un calcul (pic ~1,1 Gio,
`mem_reservation: 1g`), soit ~1,2 Gio disponibles au pire moment.

Keycloak 26.8.2 mesuré en local sous une limite de 768 Mio, tas à 50 % :
~490 Mio après démarrage, ~500 Mio en charge légère, pic 563 Mio (construction
au démarrage comprise) ; sa base ~40 Mio. Budget ~550 Mio : il reste ~650 Mio
pendant un calcul, plus 2 Gio de swap.

Limite 768 Mio (1,4 × le pic, sous les 2 × de la doctrine, faute de place) et
`oom_score_adj: 500` sans `mem_reservation` : sous la pression, c'est Keycloak
qui est récupéré ou tué en premier, jamais le calcul. À remesurer après une
semaine (`docs/conventions/resource-limits.md`). Marge de plus si besoin :
pgAdmin (~250 Mio) peut s'éteindre (`flip_planning_pgadmin_enabled`).

## Tests

`tests/keycloak_planning.tftest.hcl` (`mise run tofu-test`), tout mocké.
