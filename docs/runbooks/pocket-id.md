# Pocket ID : le fournisseur d'identité

Décision et risques : [ADR 0030](../adr/0030-pocket-id-fournisseur-identite-pilote.md)
(pilote du 05/11, clos le 07/11). Pocket ID (`id.sylvain.cloud`, rôle `pocket_id`
sur la VM Pangolin) est un fournisseur OIDC à **passkeys seuls**. Le foyer s'y
connecte : au mur Pangolin et à chaque appli qui sait faire de l'OIDC
([login-unifie-applis.md](../login-unifie-applis.md)). Le compte interne
propriétaire de l'organisation (mot de passe et 2FA, jamais relié à l'IdP)
reste le secours si Pocket ID tombe.

## Ce que ça change et ne change pas

| | Depuis le 06/11 |
|---|---|
| Mur SSO de Pangolin | la page de login d'une ressource **saute directement** vers Pocket ID (`skip_to_idp_id`, `websites.tf`). Pangolin crée l'utilisateur externe à sa première connexion et **réécrit ses rôles à chaque connexion** d'après ses groupes Pocket ID (un groupe par rôle d'appli, même nom). Les comptes internes gardent leurs rôles posés à la main et se connectent par la page de login du tableau de bord, qui garde le formulaire local |
| Clients mobiles (Immich, Karakeep, Papra, Grocy, Nextcloud, ntfy, flux) | **aucun effet** : ils passent par des jetons d'accès Pangolin, des en-têtes, des mots de passe d'application ou des chemins ouverts ([acces-mobile.md](../acces-mobile.md)), jamais par la page de login du mur |
| Applis branchées | un bouton Pocket ID **en plus** du login local, sauf BookStack, FreshRSS (web), l'interface de VictoriaLogs et Grocy, où Pocket ID (ou Pangolin pour Grocy) est le seul chemin : leur secours est plus bas |
| `id.sylvain.cloud` | public, **hors filtre FR/DE** : en voyage, la connexion Pocket ID marche sans déclarer le pays ; c'est la différence de 0002 |

## Étapes de Sylvain, dans l'ordre

Le merge de la PR ne déploie rien de visible : sans la clé SOPS de l'étape 1, ni
conteneur ni routeur (`pangolin.yaml` la saute en le disant).

1. **Clé SOPS** (`secrets/`, PR sur `homelab-secrets` puis bump ici) :
   `pocket_id_encryption_key` dans `ansible.sops.yaml`
   (`openssl rand -base64 32`, 16 octets au moins). Entrée de
   `secrets-rotation.yaml` : `kind: encryption` (sur incident seulement, pas
   d'échéance) : Pocket ID chiffre ses clés de signature avec ; une rotation
   passe par `encryption-key-rotate` (« Rotations » plus bas) avant de changer
   la clé. Puis, depuis `tofu/pangolin_config` : `tofu plan` (les moniteurs
   « Pocket ID » et « Backup Pocket ID », rouges jusqu'au déploiement) et
   `tofu apply`. Puis, depuis `ansible/` : `ansible-playbook pangolin.yaml --check
   --tags pangolin,pocket_id`, puis sans `--check`. Surveiller le premier
   démarrage : `sudo docker compose -f /opt/pocket-id/compose.yaml ps` (`healthy`) et
   `logs` (le conteneur tourne sans privilège, `read_only` : sa première
   écriture dans `data/` est le test). **Repli** si une permission est refusée :
   dans `templates/compose.yaml`, revenir à l'image sans `-distroless` (même
   version) et retirer `user:`, `read_only:` et `cap_drop:` (l'image part en
   root et rend `data/` à l'utilisateur 1000), redéployer, et corriger dans une
   PR.
2. **Premier compte administrateur**, depuis la maison seulement (tant que
   `pocket_id_setup_phase: true`, `host_vars/pangolin`, tout l'hôte refuse une
   autre IP : la page `/setup` est ouverte à qui arrive le premier) : ouvrir
   `https://id.sylvain.cloud/setup`, créer le compte (nom d'utilisateur sans
   espace : c'est l'identifiant lu par Pangolin), enregistrer le **premier
   passkey**. Puis une PR passe `pocket_id_setup_phase: false`, déployée par
   `pangolin.yaml --tags pangolin` : le routeur s'ouvre au monde. Enfin
   `pangolin.yaml --tags pocket_id` une seconde fois : la base SQLite existe,
   la sauvegarde la trouve (au premier passage elle n'existait pas encore).
3. **Passkeys sur deux appareils au moins** (téléphone, clé matérielle, poste),
   dans Pocket ID, profil, Passkeys. Tester « se connecter avec un autre
   appareil » (QR code, 5 minutes). Sans mot de passe ni TOTP, un seul passkey
   perdu est un compte à récupérer (secours ci-dessous).
4. **Clients OIDC, déclarés par Tofu** (`tofu/pangolin_config/pocket_id.tf`,
   provider `trozz/pocketid`). Le rôle `pocket_id` pose `STATIC_API_KEY`
   (clé SOPS `pocket_id_static_api_key`, la même dans les deux fichiers) ;
   `tofu apply` crée le groupe `homebox`, les clients `Homebox` et `Pangolin`
   (confidentiels, PKCE exigé, secrets en `random_password` du state) et
   l'IdP « Pocket ID » de Pangolin (clé root `pangolin_root_api_key`, alias
   `pangolin.root` : une clé d'organisation ne peut pas créer d'IdP), dont
   l'URL de rappel remplit le client `Pangolin`. Rien à recopier. Puis `ansible-playbook docker.yml --tags
   homebox` : le rôle lit le client dans les sorties du state, le bouton
   apparaît, le login local reste. **À la main** : s'ajouter au groupe
   `homebox` dans Pocket ID (Administration, Utilisateurs, son compte,
   Groupes) ; Tofu ne déclare aucun compte, pour qu'un apply ne puisse jamais
   toucher à l'administrateur. La liaison d'un compte local de Homebox par
   e-mail, et la création d'un compte OIDC inscription fermée, sont à
   confirmer à l'essai (voir [login-unifie-applis.md](../login-unifie-applis.md)).
   - **TREK** (le foyer) : groupes `trek` (accès) et `trek-admin` (admin,
     relu à chaque connexion : **s'y mettre avant sa première connexion**, sinon
     on redevient utilisateur, sauf le dernier admin que TREK garde). Comptes
     Pocket ID du foyer créés par l'administrateur (code à usage unique).
     Liaison au compte TREK existant par e-mail : refusée si Pocket ID ne le dit
     pas vérifié (`email_not_verified` ; cocher « E-mail vérifié » sur
     l'utilisateur dans Pocket ID ; le réglage global « E-mails vérifiés » n'est plus modifiable, l'env tient la configuration), ou si le compte TREK a saisi son adresse
     lui-même (`email_link_blocked`) : l'admin de TREK la confirme en la
     changeant dans le panneau d'administration. Login local gardé
     (`OIDC_ONLY=false`). L'inscription par SSO de TREK est ouverte par défaut
     (`oidc_registration`, réglage de l'admin TREK, pas une variable) : toute
     personne du groupe Pocket ID `trek` sans compte TREK en reçoit un.
     Le groupe est donc la seule barrière.
   - **HealthLog** (Sylvain seul) : s'ajouter au groupe `healthlog` dans
     Pocket ID et y cocher « E-mail vérifié » sur son compte
     (`oidc_email_unverified` sinon). Première connexion par Pocket ID : renvoi
     vers la page de login, puis une connexion par mot de passe (et 2FA
     HealthLog) dans les 10 minutes relie le compte, définitivement.
     L'inscription de HealthLog est fermée (README du rôle, étape 4) : le SSO
     ne crée aucun compte (`oidc_registration_disabled`). Si elle était
     rouverte, un compte créé par SSO n'aurait pas de mot de passe :
     `docker compose exec app node scripts/reset-password.mjs <compte>`.
   - **Beszel** (Sylvain seul ; `requires_reauthentication` : le passkey à
     chaque connexion, même avec une session Pocket ID ouverte) : s'ajouter au groupe `beszel` et cocher
     « E-mail vérifié » dans Pocket ID ; l'adresse doit être **exactement**
     celle du compte Beszel (`beszel_admin_email`), sinon PocketBase ne trouve
     aucun compte et, `USER_CREATION` étant à false, refuse. PocketBase n'a pas
     de découverte OIDC : le fournisseur se saisit à la main dans l'admin du
     hub (`/_/#/settings` : couper « Hide collection create and edit
     controls » ; collection `users`, Options, OAuth2, fournisseur OIDC) avec
     Client ID `beszel`, secret lu par `tofu output -raw
     pocket_id_beszel_client_secret` dans un terminal, Auth URL
     `https://id.sylvain.cloud/authorize`, Token URL
     `https://id.sylvain.cloud/api/oidc/token`, User info URL
     `https://id.sylvain.cloud/api/oidc/userinfo`, PKCE activé ; puis remettre
     l'interrupteur. Le secret n'est relu par aucun rôle : après une rotation
     du `random_password`, le ressaisir ici, et après une restauration ou une
     reconstruction du hub, vérifier que le fournisseur est toujours là.
     Adresses différentes (cas du 05/11 : compte Beszel créé avec l'adresse
     de service de `beszel_admin_email`) : dans l'admin PocketBase, collection
     `users`, changer l'e-mail de l'enregistrement pour celui de Pocket ID,
     `verified` coché ; `beszel_admin_email` ne sert qu'au premier démarrage du hub, mais reporter la nouvelle adresse dans `beszel_systems_user_email` (host_vars/docker) : `config.yml` la lit, et une adresse inconnue du hub le fait sortir au démarrage, en boucle (incident du 11/11).
     Mot de passe gardé.
   - **Dawarich** (le foyer, groupe `dawarich`) : chaque personne a déjà un
     compte Dawarich, est dans le groupe `dawarich`, et son e-mail Pocket ID
     est identique à celui du compte et coché « vérifié » (sinon
     `email_not_verified`, ou « requires administrator » si aucun compte ne
     correspond : `OIDC_AUTO_REGISTER=false`, rien n'est créé). À la première
     connexion, un défi demande le mot de passe Dawarich ; un compte avec 2FA
     est alors relié mais renvoyé vers la page de login, à refaire une fois.
     **Admin / utilisateur : réglé dans Dawarich** (Administration,
     Utilisateurs) : Dawarich 1.19.0 ne lit aucun rôle dans l'OIDC, pas de
     groupe `dawarich-admin`. Les traceurs gardent leur clé d'API.
   - **Immich** (le foyer, groupe `immich` ; admins aussi dans `immich-admin`,
     qui porte le claim `immich_role: admin`, relu à chaque connexion ; sans
     lui, Immich garde le rôle déjà posé) : réglé dans l'interface
     (Administration, Paramètres, Authentification OAuth) : émetteur
     `https://id.sylvain.cloud`, Client ID `immich`, secret lu par `tofu output
     -raw pocket_id_immich_client_secret` dans un terminal, scope `openid email
     profile`, claim de rôle `immich_role`, bouton « Pocket ID ». **Auto-register
     coupé** : Immich lie un compte existant par e-mail (sans exiger qu'il soit
     vérifié) et, sinon, en créerait un vide. Mobile : rappel
     `app.immich:///oauth-callback`, déclaré sur le client (si l'appli le
     refuse, cocher l'override mobile avec
     `https://photos.sylvain.cloud/api/oauth/mobile-redirect` et l'ajouter au
     client). Connexion par mot de passe gardée (`passwordLogin`). Le secret
     n'est relu par aucun rôle : le ressaisir après une rotation.
     **Quota de stockage : réglé dans Immich** (Administration, Utilisateurs),
     aucun claim `immich_quota` dans Pocket ID. Immich 3.3.5
     (`auth.service.ts`, `syncOAuthClaims`) réapplique ce claim **à chaque
     connexion, comptes existants compris** : posé sur un groupe (20 Go), il
     ramènerait un compte à 100 Go à 20 Go. Absent, Immich ne touche pas au
     quota. Le « quota par défaut » de l'interface ne sert qu'aux comptes
     créés par OIDC, donc jamais tant que l'auto-register est coupé. Pour
     piloter un jour les quotas depuis Pocket ID : un claim par utilisateur
     (interface de Pocket ID, Tofu ne déclare pas les utilisateurs), jamais
     sur le groupe, au prix d'un quota réglé à deux endroits ; priorité
     utilisateur / groupe dans Pocket ID non vérifiée.
   - **Wishlist** (le foyer, groupe `wishlist`) : réglé dans l'interface
     (Administration, Paramètres, OIDC) : URL de découverte
     `https://id.sylvain.cloud/.well-known/openid-configuration`, Client ID
     `wishlist`, secret par `tofu output -raw pocket_id_wishlist_client_secret`,
     nom « Pocket ID », **auto-register coupé** (liaison par e-mail ; refusée
     si Pocket ID marque l'e-mail non vérifié). Pas de rôle par claim : les
     admins se règlent dans Wishlist. Mot de passe gardé.
   - **Karakeep** (le foyer, groupe `karakeep`) : rien à saisir, le rôle
     `karakeep` pose `OAUTH_*` depuis les sorties Tofu. Liaison par e-mail
     (`OAUTH_ALLOW_DANGEROUS_EMAIL_ACCOUNT_LINKING`, sûr ici : seul
     l'administrateur crée les comptes Pocket ID) ; `DISABLE_SIGNUPS` empêche
     toute création. Mot de passe gardé : l'appli mobile et l'extension
     l'utilisent (ou une clé d'API). Pas de rôle par claim.
   - **Papra** (le foyer, groupe `papra`) : rien à saisir, le rôle `papra`
     pose `AUTH_PROVIDERS_CUSTOMS` (fournisseur `pocket-id`, PKCE) depuis les
     sorties Tofu. Liaison par e-mail : better-auth 1.6.11 exige l'e-mail
     vérifié **des deux côtés** (`requireLocalEmailVerified`, non réglable
     dans Papra). Un compte créé par inscription a `email_verified = 0` :
     le bouton Pocket ID finit sur `/api/auth/error` (« account not linked »).
     Avant la première connexion de chacun, depuis `ansible/` :
     `ansible docker -b -m shell -a "cd /opt/apps/papra/app-data/db && sqlite3 db.sqlite \"VACUUM INTO 'db.sqlite.avant-verif'\" && sqlite3 db.sqlite \"UPDATE users SET email_verified=1 WHERE email='<adresse>'; SELECT changes();\""`
     (doit afficher `1` ; fait pour Sylvain le 2026-11-06). L'inscription
     fermée empêche toute création. Mot de passe gardé. Pas de rôle par claim.
   - **Yamtrack** (le foyer, groupe `yamtrack`) : rien à saisir, le rôle pose
     `SOCIAL_PROVIDERS` et `SOCIALACCOUNT_PROVIDERS` (allauth, PKCE). **Aucune
     liaison automatique** : chacun se connecte une fois par mot de passe, puis
     Réglages, Comptes, « Manage Account Connections », Pocket ID.
     `REGISTRATION=False` ferme aussi l'inscription par OIDC. Mot de passe
     gardé.
   - **Open WebUI** (le foyer, groupe `openwebui`) : rien à saisir, le rôle
     `openwebui` pose `OAUTH_*` et `OPENID_PROVIDER_URL` depuis les sorties
     Tofu (PKCE S256, rappel `/oauth/oidc/callback`). **Sylvain se connecte le
     premier** : le premier compte de la base est administrateur, les
     suivants sont créés au premier login avec le rôle `user`
     (`ENABLE_OAUTH_SIGNUP`). Liaison par e-mail sans contrôle de
     vérification (comme Karakeep : sûr tant que `ALLOW_OWN_ACCOUNT_EDIT` reste
     à `false`). Mot de passe gardé (secours : README du rôle).
   - **Postiz** (le foyer, groupe `postiz`, sur flip) : rien à saisir, le rôle
     `postiz` pose `POSTIZ_OAUTH_*` depuis les sorties Tofu (sans PKCE, rappel
     `/settings`). **Sylvain se connecte le premier.** Compte créé au premier
     login, lié par e-mail ; pas de mot de passe local, donc pas de secours
     dans l'appli (README du rôle).
   - **MediaManager** (essai, NAS, groupe `mediamanager`) : rien à saisir, le
     rôle pose `[auth.openid_connect]` ; **déploiement à la main**
     (`nas.yml --tags mediamanager`, jamais par la CI). Pas de PKCE.
     Liaison par e-mail **sans contrôle de vérification** et **aucun
     interrupteur d'inscription** : tout membre du groupe peut se créer un
     compte, le groupe est la seule barrière. Admin : `admin_emails`, à
     l'inscription seulement. Rappel bâti depuis la requête
     (`FORWARDED_ALLOW_IPS` pour le https), déclaré pour 443 et 8443.
   - **Nextcloud** (le foyer, groupe `nextcloud`) : rien à saisir, le rôle
     installe l'app `user_oidc` (magasin d'applis) et pose le fournisseur
     « Pocket ID » par `occ user_oidc:provider` (rejoué à chaque passage).
     **Liaison par uid** (`preferred_username`), jamais par e-mail : le nom
     d'utilisateur Pocket ID doit être l'uid Nextcloud (vérifié le
     2026-11-06 : `sylvain`, `marielea` ; un uid ne se renomme pas, on aligne
     Pocket ID). Aucune création de compte (`disable_account_creation`), pas
     de synchro de groupes (elle retirerait `admin`) : groupes et admin dans
     Nextcloud. Formulaire local gardé (`/login?direct=1`), mots de passe
     d'application inchangés pour les clients.
   - **Proxmox** (hors mur : LAN et ressource privée `pve.internal`) : realm
     OpenID `pocketid` posé par `pve.yml --tags pve_oidc` (à la main). Groupes
     Pocket ID `proxmox-admin` (Administrator) et `proxmox-auditor`
     (PVEAuditor, lecture) → groupes PVE `<groupe>-pocketid`, réécrits à
     chaque connexion ; utilisateurs `<nom>@pocketid` créés au premier login.
     Pas de PKCE (proxmox-openid ne l'envoie pas). Rappel : l'origine de la
     page, `https://pve.sylvain.cloud:8006` et `https://192.168.1.26:8006`
     (une autre adresse d'accès : l'ajouter au client). `root@pam` reste le
     secours.
   - **Jellyfin** (NAS, le foyer, groupes `jellyfin` et `jellyfin-admin`) :
     greffon SSO-Auth posé par le rôle `jellyfin` (`nas.yml --tags jellyfin`,
     à la main), fournisseur `pocketid`, rappel
     `https://media.sylvain.cloud/sso/OID/redirect/pocketid`. À la main une
     fois : le bouton dans Tableau de bord, Général, Branding (README du rôle)
     et `sylvain` dans `jellyfin-admin`. Mots de passe et Quick Connect
     gardés : secours.
   - **Prowlarr et qBittorrent** (NAS, groupe `mediamanager-admin`) : aucun
     OIDC natif, oauth2-proxy (rôle `nas_proxy`, `nas.yml --tags nas_proxy`, à
     la main) en forwardAuth du Traefik du NAS ; rien à saisir, `sylvain` dans
     le groupe suffit. Pocket ID seul (Prowlarr en `External`, qBittorrent
     sans mot de passe pour le réseau du proxy) ; secours si Pocket ID ou le
     proxy tombe : tunnel SSH vers `127.0.0.1:8080` (qBittorrent ; Prowlarr
     seulement avec le login local), ou
     `mediamanager_local_login: true` (README de `mediamanager`, « Login local
     de secours »).
   - **Immich Power Tools** (le foyer, groupe `immich-power-tools`, et
     `immich` pour passer le client Immich) : plus de clé d'API, chacun se
     connecte par « Se connecter avec Pocket ID » (OAuth d'Immich, rappel
     `https://power-tools.sylvain.cloud/api/auth/oauth/callback` sur le client
     `immich`) et agit avec son propre compte Immich.
   - **VictoriaLogs** (groupe `victoria-logs`) : SSO de vmauth, rien à
     saisir, le rôle `victoria_logs` pose `sso:` depuis les sorties Tofu ;
     plus d'interface en Basic (le compte `sylvain` ne sert plus qu'aux
     scripts, `/select/logsql/query`). Agents et Homepage inchangés.
   - **FreshRSS** (le foyer, groupe `rss`) : rien à saisir, le rôle `rss`
     active l'OIDC de l'image et passe `auth_type` à `http_auth`. **Plus de
     formulaire web** : le nom d'utilisateur Pocket ID est le compte FreshRSS
     (créé s'il manque). API (applis mobiles, Homepage) inchangée. Secours :
     README du rôle `rss`.
   - **BookStack** (le foyer, groupe `wiki`) : `AUTH_METHOD=oidc` posé par le
     rôle `wiki`, **exclusif**. Avant la bascule, poser l'identifiant Pocket ID
     (`users.id` de la base Pocket ID = `sub`) dans `external_auth_id` de
     chaque compte BookStack (table `users`, fait le 2026-11-06 pour Sylvain
     et Marie-Léa) ; sans lui, BookStack refuse ou crée un compte. Rôles dans
     BookStack. Secours : `wiki_oidc_force_standard: true`, relancer le rôle.
   - **Grocy** (groupe `grocy`) : pas d'OIDC ; Grocy fait confiance à
     l'en-tête `Remote-User` de Pangolin (nom d'utilisateur Pangolin = Pocket
     ID), badger efface tout `Remote-User` venu du client. Plus de formulaire ;
     l'appli Android garde sa clé d'API. Sondes sur `/robots.txt`. Secours :
     `grocy_proxy_auth_enabled: false`, relancer le rôle.
   - **Actual Budget** (PikaPods, hors Pangolin, groupe dédié `actual`) :
     réglé dans son interface (Paramètres, Avancé, « Start using OpenID ») :
     émetteur `https://id.sylvain.cloud`, Client ID `actual`, secret par
     `tofu output -raw pocket_id_actual_client_secret`, adresse du serveur
     `https://budget.sylvain.cloud`. Le premier login OpenID devient
     propriétaire et reprend les budgets ; les autres comptes se créent dans
     l'annuaire d'Actual, nom = nom d'utilisateur Pocket ID.
   - **Tuiles vitrine** : chaque appli du mur sans client réel a un client
     public `vitrine-<appli>` (`pocketid_client.launcher`, généré depuis
     `local.websites`), jamais utilisé pour se connecter, pour paraître dans
     « Mes applis » de Pocket ID aux seuls membres du groupe de son rôle. Une
     nouvelle appli y entre d'elle-même (test `tofu test`).
5. **Accès au mur Pangolin = groupes Pocket ID.** Mettre la personne dans le
   groupe Pocket ID de chaque appli (nom technique = le rôle Pangolin : `immich`,
   `trek`… ; nom affiché = celui de l'appli, sans préfixe : tout groupe
   d'appli vaut accès au mur Pangolin), puis se connecter à la page de login de Pangolin avec « Pocket
   ID » : Pangolin crée l'utilisateur externe et lui donne ces rôles, à chaque
   connexion. Un admin d'appli (`trek-admin`) est aussi dans le groupe de
   base (`trek`), sinon le mur l'arrête. Aucun groupe reconnu : « No policies
   matched ». Un utilisateur externe créé à la main avant (le cas de Sylvain
   jusqu'au 06/11) n'est jamais synchronisé : le supprimer dans Pangolin, il
   revient à la connexion suivante. Le compte interne n'est ni lié ni modifié.
   **Licence Enterprise activée exigée** (page Licence de Pangolin) : sans
   elle, Pangolin 1.25.3 ne garde que le premier rôle, sans prévenir.

**Test de restauration rouge, attendu.** Dès le merge, le test planifié échoue
pour Pocket ID : aucune archive avant l'étape 2 et la seconde passe de
`--tags pocket_id`, et `oidc_clients` doit contenir au moins une ligne, donc rien
de vert avant le premier client de l'étape 4 suivi d'une sauvegarde.

## Inviter le foyer (lien d'inscription)

Inscription par lien seulement (`ALLOW_USER_SIGNUPS=withToken`, rôle
`pocket_id`) : sans lien, personne ne crée de compte.

1. Administration → Users → Add User → **Create Signup Token** : expiration
   courte (7 jours), autant d'utilisations que de personnes, groupes des applis
   à ouvrir (`trek`, `dawarich`…).
2. Envoyer le lien. Chacun crée son compte et son passkey, déjà dans les
   groupes ; l'e-mail de vérification part tout seul (`EMAIL_VERIFICATION=optional`),
   « E-mail vérifié » se coche au clic, plus à la main.
3. « View Active Signup Tokens » : révoquer le lien une fois tout le monde inscrit.

Les comptes créés avant le SMTP restent non vérifiés : la case se coche encore
à la main pour eux.

## Ce que Pangolin lit des claims de Pocket ID

Vérifié dans les docs ([Pangolin](https://docs.pangolin.net/manage/identity-providers/pocket-id),
[Pocket ID](https://pocket-id.org/docs/guides/scopes-and-claims)) : le jeton
d'identité de Pocket ID porte `sub`, `preferred_username`, `email`, `name`
selon les scopes ; **`groups`** (liste des noms *internes* des groupes, pas
les noms affichés) **seulement avec le scope `groups`**, que le guide de Pangolin
ne demande pas : `pocket_id.tf` l'ajoute. Pangolin lit un identifiant
(`preferred_username`, modifiable dans Pocket ID : le renommer sans le suivre
dans Pangolin coupe le compte externe) et évalue ses expressions de rôle (JMESPath,
chaînes entre `'`) sur le jeton **à chaque login** ; un rôle inexistant, ou aucune
règle qui correspond, donne « No policies matched ». Plusieurs rôles par
utilisateur : licence EE activée seulement (`fullRbac`, lu dans
`validateOidcCallback.ts` de la 1.25.3 : sans elle, seul le premier nom est
gardé). Dans ce même code : la règle peut rendre une liste de noms, les noms
sans rôle Pangolin sont ignorés, et les rôles ne sont réécrits que pour un
utilisateur créé par Pangolin lui-même (`auto_provision`). La règle
(`pocket_id.tf`) filtre `groups` sur la liste des rôles d'applis : un groupe
Pocket ID nommé `Admin` ou `Member` ne donne rien. Un `groups` absent donne
une liste vide, donc un refus.

## Bascule (faite les 05 et 06/11)

Pilote sur Homebox le 05/11, puis toutes les applis OIDC et le foyer le 06/11,
BookStack, FreshRSS et vmauth (OIDC exclusif) compris, et le saut direct du mur
vers Pocket ID. Pilote clos le 07/11 sans attendre ses critères (ADR 0030, « Fin
du pilote ») : chaque montée de version de Pocket ID passe donc par l'audit
ci-dessous. Comptes internes Pangolin gardés.

## Audit de sécurité (après chaque montée de version)

`mise run audit-pocket-id` (depuis le poste, environnement SOPS de mise) :
`.github/scripts/pocket_id_audit.py`, environ 2 minutes, code de sortie 1 si
un contrôle échoue.

- **Passif** : découverte OIDC (S256, pas d'`alg none`, pas d'implicite),
  JWKS sans partie privée, en-têtes, CORS, chemins exposés, configuration
  publique (inscription fermée), version comparée aux avis publiés.
- **Sans compte** : API admin, userinfo (dont un JWT `alg=none` forgé),
  token, introspection, device flow refusés ; 40 clés API fausses.
- **Flux complet**, avec un groupe, deux clients et un utilisateur jetables
  `pid-audit-*` (supprimés à la fin, et les restes d'un passage interrompu au
  début ; ils passent dans le journal d'audit) : refus hors groupe, PKCE,
  `redirect_uri` piégées, codes entre clients, rejeu de code, refresh après
  rotation et après retrait du groupe.

Résultats connus de la v2.19.1 (06/11/2026), à ne pas reprendre pour une
régression : PKCE `plain` accepté (activé en dur), ancien refresh token
valable une minute après rotation (période de grâce voulue). Les en-têtes
`nosniff`, `Referrer-Policy`, `Permissions-Policy` et CORP sont posés par le
middleware `pocket-id-headers` du rôle pangolin (pas de COOP : fenêtre
surgissante de Beszel).

Scanners génériques, à la demande, images épinglées par digest :

```bash
A=$(mktemp -d); chmod 777 "$A"
podman run --rm -v "$A:/out:Z" docker.io/drwetter/testssl.sh@sha256:64bab3c1fd8eee440f68d5e020dd633c1f2d375fe0ae593bdfec2725110a7e29 \
  --quiet --color 0 --jsonfile /out/testssl.json id.sylvain.cloud
podman run --rm -v "$A:/zap/wrk:Z" ghcr.io/zaproxy/zaproxy@sha256:9624669db72f54d86c4b46a7064518bd9bf79d8c61a4c31befa9923489f328af \
  zap-baseline.py -t https://id.sylvain.cloud -m 1 -J zap.json -I
podman run --rm -v "$A:/root/nuclei-templates:Z" docker.io/projectdiscovery/nuclei@sha256:582d5546902e67052097cb2d07296c642d50a1afc5e44623cb038845df9a32eb -ut
podman run --rm -v "$A:/root/nuclei-templates:Z" docker.io/projectdiscovery/nuclei@sha256:582d5546902e67052097cb2d07296c642d50a1afc5e44623cb038845df9a32eb \
  -u https://id.sylvain.cloud -rl 5 -c 5 -etags dos,fuzz,intrusive,bruteforce -duc
```

Avant les scanners, ton IP en liste blanche CrowdSec le temps du passage
(expire seule), sur Pangolin : `sudo docker exec crowdsec cscli allowlists
create pocket-id-audit -d "audit Pocket ID"` (une fois, l'`add` échoue sans
elle) puis `sudo docker exec crowdsec cscli allowlists add pocket-id-audit
<ip> -e 4h` (`docs/runbooks/crowdsec.md`).

## Secours

- **L'IdP tombe** (moniteur « Pocket ID » rouge, `docker compose ps`) :
  redémarrer : `sudo docker compose -f /opt/pocket-id/compose.yaml up -d`,
  journaux avec `logs`. Si Pangolin redémarre, le conteneur reste sur le réseau
  `pangolin` (`docker compose down` de la pile Pangolin dit alors qu'il ne peut
  pas le retirer : sans conséquence). Le temps qu'il revienne :
  - **mur** : une session se prend avec le
    compte interne propriétaire, par la page de login du **tableau de bord**
    Pangolin (formulaire local gardé), dont la session ouvre les ressources ;
  - **applis à login local** : leur mot de passe, comme avant ;
  - **BookStack** : `wiki_oidc_force_standard: true` (rôle `wiki`, à relancer) rend le login
    standard ; **FreshRSS** : `auth_type` à `form` et `OIDC_*` retirés sur l'hôte
    (`ansible/roles/rss/README.md`) ; **Grocy** : `grocy_proxy_auth_enabled:
    false` (rôle `grocy`, à relancer) rend le login Grocy ; **VictoriaLogs** : depuis l'hôte docker,
    interroger `127.0.0.1:9428` avec le compte Basic `sylvain`
    (`/select/logsql/query` seulement, hors hôte SSO).
- **Tous les passkeys sont perdus** : un code créé par l'administrateur **sur
  l'hôte** (pas besoin d'un compte), valable 1 heure, une seule fois :
  `sudo docker compose -f /opt/pocket-id/compose.yaml exec pocket-id /app/pocket-id one-time-access-token <nom d'utilisateur>`.
  Ouvrir l'URL affichée, enregistrer un nouveau passkey (deux), supprimer
  les anciens. Même chemin si le compte perdu est l'administrateur. Pour un
  membre du foyer, l'admin peut aussi lui envoyer le code par e-mail (menu ⋯ de
  l'utilisateur, « Send Email ») ; jamais de code demandé par l'utilisateur
  lui-même (`EMAIL_ONE_TIME_ACCESS_AS_UNAUTHENTICATED_ENABLED` reste à false :
  ce serait « la boîte mail ouvre tout »).
- **Rotations** (depuis le dossier `/opt/pocket-id`, `sudo docker compose exec
  pocket-id /app/pocket-id …`) :
  - `ENCRYPTION_KEY` (nouvelle clé : `openssl rand -base64 32`, 16 octets au
    moins, sinon le rôle refuse de la déployer) : vérifier d'abord que la
    sauvegarde Borg de la nuit est verte (le rechiffrement ne se défait pas) ; puis `encryption-key-rotate --new-key
    <nouvelle clé>` rechiffre les données (la clé reste dans l'historique du
    shell : la saisir depuis une variable, `--new-key "$NEW"`), **puis** la
    nouvelle clé dans SOPS
    (`pocket_id_encryption_key`), `pangolin.yaml --tags pocket_id`, et
    `last_rotated` dans `secrets-rotation.yaml`. Changer la clé SOPS d'abord
    rend les clés de signature illisibles.
  - Clé de signature des jetons : `key-rotate` (RS256 par défaut ; `--alg
    ES256` seulement si tous les clients le lisent). Invalide tous les jetons
    émis : chaque appli redemande une connexion. Puis redémarrer le conteneur.
- **Mise à jour** : lire les notes de version et le [guide de mise à jour](https://pocket-id.org/docs/setup/upgrading).
  La base migre au démarrage et Pocket ID refuse de repartir en arrière
  (`ALLOW_DOWNGRADE=true` l'impose, à vos risques) : le retour arrière, c'est
  l'archive borg d'avant. Le tag est épinglé en v2 : une v3 (interface refaite)
  est une montée majeure, jamais automatique.
- **Restauration** : [sauvegarde-et-restauration.md](sauvegarde-et-restauration.md),
  dépôt `pocket_id` du sous-compte de Pangolin ; même clé de chiffrement que
  celle du `.env` archivé.
- **Retour arrière** : ADR 0030 (décision, puis « Fin du pilote »).
