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
- L'enregistrement dynamique des clients MCP, ouvert depuis le 25/11/2026 aux
  seuls Claude (web) et Le Chat (plus bas, hôtes de confiance hors Tofu) ;
  aucun scope optionnel (ni `offline_access`).

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
   mot de passe temporaire. Ajouter un compte permanent dans le realm master
   si l'on veut, mais **garder le bootstrap `admin`** et son mot de passe de
   SOPS : le provider de ce module s'y connecte (`keycloak_admin_user`,
   `prod_planning_keycloak_admin_password`), le supprimer ou en changer le mot
   de passe dans la console casse le `tofu plan` suivant.
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
depuis leurs serveurs. Ouvert le 25/11/2026 (décision de Sylvain) :

- **Trusted Hosts** (anonymous) : seuls `claude.ai`, `claude.com` et
  `chat.mistral.ai` ; **toutes** les URI de redirection d'un client doivent y
  être (`client-uris-must-match`), d'où qu'il appelle
  (`host-sending-registration-request-must-match` faux : les serveurs des
  assistants n'ont pas d'adresse stable). Un code ne repart que chez
  l'assistant.
- **Max Clients Limit** : 20 (au lieu de 200), dans Tofu.
- Gardées telles que Keycloak les pose : écran de consentement, scopes du realm
  seulement (aucun optionnel : `offline_access` refusé), types de mappeurs
  bornés, Full Scope Disabled.
- Un client enregistré n'ouvre rien seul : il faut une personne qui se
  connecte au realm ET un compte actif avec un droit dans l'application.

Vérifié le 25/11/2026 contre le vrai endpoint
(`/auth/realms/planning/clients-registrations/openid-connect`) :
- 201 pour `claude.ai`, `claude.com` et `chat.mistral.ai` ;
- 403 pour une URI hors liste, pour une bonne URI accompagnée d'une hors liste,
  pour `claude.ai.evil.example`, et pour `scope=offline_access` ;
- le client créé a `planning-mcp-audience` dans ses scopes par défaut et le
  consentement exigé. Les clients de test ont été supprimés.

**Trusted Hosts est hors de Tofu** : ses hôtes sont une valeur multiple que le
provider (`config` en `map(string)`) ne sait pas écrire (« a##b » devient un
seul hôte, qui refuse tout). Pour la changer, depuis le dépôt :

```bash
cd ansible && mise exec -- ansible flip -m shell -a 'docker exec flip-planning-keycloak bash -c "export HOME=/tmp; /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/auth --realm master --user \$KC_BOOTSTRAP_ADMIN_USERNAME --password \"\$KC_BOOTSTRAP_ADMIN_PASSWORD\" && /opt/keycloak/bin/kcadm.sh update components/<id Trusted Hosts> -r planning -s '"'"'config.trusted-hosts=[\"claude.ai\",\"claude.com\",\"chat.mistral.ai\"]'"'"'; rc=\$?; rm -rf /tmp/.keycloak; exit \$rc"'
```

L'id : console › realm `planning` › Clients › Client registration › Anonymous
access policies › Trusted Hosts (dans l'URL). Fermer : liste vide (pas
encore essayé : relire la valeur en base après coup). Sur un
realm recréé, refaire cette commande, et `tofu import
'keycloak_realm_client_registration_policy.max_clients' 'planning/<id Max Clients Limit>'`
avant l'apply (le plan doit montrer une mise à jour en place, jamais une
création ; pas de bloc `import`, il fait paniquer `tofu test`).

## Fournisseur fédéré (Pocket ID)

Le bouton « Pocket ID » de la page de connexion du realm
(`identity_provider.tf`, alias `pocket-id`) : la répétition d'un client qui
branche son propre fournisseur (ADFS…). L'application ne change pas : elle ne
voit que Keycloak, même émetteur, même client `planning-app`.

- Côté Pocket ID : client `flip-planning` (`tofu/pangolin_config/pocket_id.tf`),
  réservé au groupe `flip-planning` (celui du rôle Pangolin), rappel
  `/auth/realms/planning/broker/pocket-id/endpoint` (hors mur Pangolin). Son
  secret passe d'un state à l'autre (sortie
  `pocket_id_flip_planning_client_secret`), ni SOPS ni console.
- Ordre : apply de `tofu/pangolin_config` (skill `pangolin-config-plan` :
  `random_password`, le client, la vitrine `vitrine-flip_planning` détruite),
  puis apply de ce module.
- Première connexion : adresse déjà dans le realm → Keycloak demande son mot
  de passe pour lier ; sinon il crée le compte (l'inscription fermée ne
  bloque pas le broker), qui n'a aucun droit tant que l'application n'a pas
  de compte actif à cette adresse. Adresse marquée vérifiée (`trust_email`),
  nom et adresse relus à chaque connexion (`sync_mode = FORCE`).
- Tester sans brancher l'application : console de compte
  `https://flip-planning.sylvain.cloud/auth/realms/planning/account/`,
  « Pocket ID ». Une personne hors du groupe `flip-planning` est refusée chez
  Pocket ID.
- Retirer : supprimer `identity_provider.tf` (les comptes liés restent, leur
  lien se retire dans la console, Users › Identity provider links), puis, côté
  `pangolin_config`, le client, sa sortie et `"flip-planning"` de
  `local.pocket_id_oidc_roles` (sinon la tuile vitrine ne revient pas).

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
semaine (`docs/conventions/resource-limits.md`). pgAdmin (~250 Mio) a été retiré le 25/11/2026 pour la marge.

## Tests

`tests/keycloak_planning.tftest.hcl` (`mise run tofu-test`), tout mocké.
