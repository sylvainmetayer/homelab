# Pocket ID : pilote du fournisseur d'identité

Décision et risques : [ADR 0030](../adr/0030-pocket-id-fournisseur-identite-pilote.md).
Pocket ID (`id.sylvain.cloud`, rôle `pocket_id` sur la VM Pangolin) est un
fournisseur OIDC à **passkeys seuls**. Le pilote concerne **le compte de
Sylvain uniquement** : le foyer ne change rien, les comptes internes de Pangolin
(dont le compte interne propriétaire de l'organisation, mot de passe et 2FA,
le secours si Pocket ID tombe) restent le chemin de tout le monde.

## Ce que ça change et ne change pas

| | Pilote |
|---|---|
| Mur SSO de Pangolin | comptes internes **inchangés** (rôles posés dans l'interface). Un bouton « Pocket ID » s'y ajoute : Pangolin crée l'utilisateur externe à sa première connexion et **réécrit ses rôles à chaque connexion** d'après ses groupes Pocket ID (un groupe par rôle d'appli, même nom) |
| Clients mobiles (Immich, Karakeep, Papra, Grocy, Nextcloud, ntfy, flux) | **aucun effet** : ils passent par des jetons d'accès Pangolin, des en-têtes, des mots de passe d'application ou des chemins ouverts ([acces-mobile.md](../acces-mobile.md)), jamais par la page de login du mur. Rien à reconfigurer, aucun chemin ouvert ajouté |
| Navigateur, PWA (HealthLog…) | inchangés tant que le mur reste sur les comptes internes ; à la bascule, le login passe par Pocket ID dans le navigateur, les en-têtes `P-Access-Token-*` des applis ne bougent pas |
| Homebox | un bouton « Se connecter avec Pocket ID » **en plus** du login local, qui reste le secours |
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
     `verified` coché ; la variable ne sert qu'au premier démarrage du hub.
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

## Plan de bascule (hors pilote, une PR chacune)

1. Pilote : Pocket ID, Homebox, un utilisateur externe Pangolin (ce runbook).
2. Quelques semaines sans incident : les moniteurs verts, le test de
   restauration vert, les passkeys testés, une montée de version passée.
3. Le mur : plus d'applis (Immich, TREK, Wishlist, Dawarich, Beszel, Nextcloud,
   Karakeep, [ordre de login-unifie-applis.md](../login-unifie-applis.md)), le
   foyer invité dans Pocket ID (auto-provision et règle de groupes en place depuis le
   06/11 : il reste à vérifier la licence EE et le claim `groups`). Comptes internes gardés.
4. BookStack, FreshRSS, vmauth (OIDC exclusif) en dernier, si le gain vaut le
   login local perdu.

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

- **L'IdP tombe** (moniteur « Pocket ID » rouge, `docker compose ps`) : le mur
  Pangolin et les applis ne dépendent pas de lui pendant le pilote (comptes
  internes, login local de Homebox). Redémarrer : `sudo docker compose -f
  /opt/pocket-id/compose.yaml up -d`, journaux avec `logs`. Si Pangolin
  redémarre, le conteneur reste sur le réseau `pangolin` (`docker compose down` de
  la pile Pangolin dit alors qu'il ne peut pas le retirer : sans conséquence).
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
- **Retour arrière du pilote** : ADR 0030.
