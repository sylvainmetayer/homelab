# Accès sans le SSO : applis mobiles, flux, liens de partage

Toutes les ressources publiques de Pangolin sont derrière le SSO (le « mur »
de connexion Pangolin), sauf deux. Mais un téléphone qui synchronise ses
contacts, une appli mobile, un assistant hébergé ou un visiteur qui ouvre un
lien de partage n'a pas de session Pangolin. Ce document recense, appli par
appli, ce qui passe **sans** le SSO, quel client s'en sert et ce qui protège
le contenu derrière. C'est le « mode mixte » : navigateur derrière le SSO,
clients non interactifs par des ouvertures étroites.

Il décrit `tofu/pangolin_config` au 2026-10-30. Le code fait foi : chaque
liste de chemins est la `local.<app>_*_paths` de `website_<app>.tf`, avec en
commentaire la vérification faite par l'appli pour chaque chemin, et la
liste complète des ouvertures est écrite en toutes lettres dans le test
`path_bypasses_open_exactly_the_reviewed_paths`
(`tofu/pangolin_config/tests/invariants.tftest.hcl`). Un chemin ajouté ou
retiré là doit l'être ici aussi.

## L'ordre des règles

Badger (le middleware de Pangolin dans Traefik) lit les règles d'une
ressource par priorité croissante. La première qui correspond décide, et les
règles passent **avant** le SSO (`rules.tf`) :

| Priorité | Règle | Effet |
|---|---|---|
| 1 | `DROP` des chemins qui contiennent un `\` (`backslash_guard`), sur toute ressource qui a une règle de chemin | Pangolin ne normalise pas `\`, que Node change en `/` : `/shared/..\..\api/trips` passerait pour `/shared/*` |
| 2 à 9 | `ACCEPT` de chemin (`local.path_bypasses`, 2 à 6 aujourd'hui), les trois `PASS` de chemin (TREK `/mcp`, Beszel, VictoriaLogs, à 3) | `ACCEPT` : servi tout de suite, **sans SSO et sans filtre pays**. `PASS` : saute les règles pays, garde l'authentification Pangolin |
| 9 | `ACCEPT` de l'IP de la maison (`home_ip`, Immich, Dawarich, TREK) | toute la ressource, sans SSO, depuis la connexion de la maison |
| 10, 11 | `PASS` pays FR, DE | vers l'authentification (SSO) |
| 20 | `PASS` pays de voyage (`var.travel_countries`) | idem, jusqu'à la date de fin |
| 99 | `DROP` tous pays | refus |

Conséquence : un `ACCEPT` de chemin répond au **monde entier**. On ne peut pas
écrire « ce chemin, depuis la France seulement » : une règle ne porte que sur
un critère, et un `ACCEPT` placé derrière le `PASS` FR ne serait jamais
atteint. Ce qui protège ces chemins, c'est le secret de l'appli (jeton de
partage, mot de passe, clé d'API, signature), jamais Pangolin.

## Chemins ouverts sans SSO (`ACCEPT`)

| Appli (ressource) | Chemins publics | Client | Ce qui protège |
|---|---|---|---|
| Dawarich (`tracks.sylvain.cloud`) | `/s/*`, `/api/v1/shared/*`, `/cable`, `/shared/*`, `/api/v1/maps/hexagons`, `/assets/*`, `/maps_maplibre/*`, `/site.webmanifest`, `/favicon.ico` | lien de partage (trajet, trace, carte en direct), statistiques du mois partagées | UUID aléatoire, expiration, révocation, phrase magique facultative ; `/shared/...` : `sharing_uuid` et `public_accessible?`. `/cable` et `/api/v1/maps/hexagons` acceptent aussi la session Rails ou une clé d'API (déjà des identifiants complets du compte) |
| Flip Planning (`flip-planning.sylvain.cloud`) | `/mcp/*` | assistants hébergés (Claude, ChatGPT, Le Chat, Gemini) | clé partagée `PLANNING_MCP_API_KEY` (en-tête `X-Api-Key`), 401 sans elle |
| Demo Planning (`demo-planning.sylvain.dev`) | `/mcp/*` | idem | sa propre `PLANNING_MCP_API_KEY`, distincte de la production |
| Demo Planning KC (`demo-planning-kc.sylvain.dev`) | `/auth/*` | l'appli elle-même au démarrage (découverte du realm, clés), navigateurs | la connexion de Keycloak. La console d'admin (`/auth/admin`) est joignable du monde entier, derrière ce seul login : accepté pour un banc de test. En pause depuis octobre 2026 : ressource désactivée, plus rien n'y répond |
| Karakeep (`keep.sylvain.cloud`) | `/public/lists/*`, `/_next/static/*`, `/api/public/*`, `/api/trpc/publicBookmarks.getPublicBookmarksInList`, `/api/v1/rss/lists/*` | lien d'une liste publique, son flux RSS | liste marquée publique ; images et fichiers signés par le serveur, avec expiration ; RSS d'une liste privée seulement avec son `rssToken`. La procédure tRPC est écrite en entier : `publicBookmarks.*` laissait passer un lot tRPC avec `apiKeys.exchange` |
| Monica (`crm.sylvain.dev`) | `/dav/*`, `/.well-known/carddav`, `/.well-known/caldav` | contacts et agenda du téléphone (CardDAV, CalDAV) | HTTP Basic avec un jeton d'accès personnel de Monica (pas le mot de passe du compte). **Désactivés** aujourd'hui, voir « Verrouillage PHP » |
| Nextcloud (`sylvain.cloud`, l'apex), clients | `/status.php`, `/index.php/204`, `/remote.php/*`, `/ocs/v1.php/*`, `/ocs/v2.php/*`, `/index.php/login/v2` (exact), `/login/v2/poll`, `/index.php/login/v2/poll`, `/index.php/core/wipe/*`, `/index.php/core/preview`, `/index.php/core/preview.png`, `/index.php/apps/files_trashbin/preview`, `/index.php/apps/files_versions/preview`, `/index.php/apps/files/api/v1/thumbnail/*`, `/.well-known/caldav`, `/.well-known/carddav` (`local.nextcloud_client_paths`) | clients de synchronisation (bureau, Android, iOS), DAVx5, Thunderbird | mot de passe d'application seulement sur DAV et OCS (`token_auth_enforced`, rôle `nextcloud`) ; la moitié navigateur du login flow v2, le formulaire de connexion et les réglages restent derrière le SSO. Tout OCS est ouvert : un mot de passe d'application administrateur y atteint aussi l'API de provisioning |
| Nextcloud, partages | `/s/*`, `/public.php/*`, l'API et les aperçus de `files_sharing`, theming, `/dist/*`, les dossiers statiques de `/core`, les fichiers statiques des applis (`/apps/*/js/*`… et `/custom_apps`), `/csrftoken`, la visionneuse PDF, les points publics de Text (`local.nextcloud_share_paths`, liste complète dans le test) | visiteur d'un lien de partage public | jeton aléatoire du partage, mot de passe et expiration facultatifs, vérifiés par `files_sharing`. `/apps/*/js/*` et ses voisins valent pour tout chemin de `/apps` qui contient un segment `js` (`css`, `img`, `l10n`) : sans SSO, mais pas sans l'authentification de Nextcloud. `/core/*` n'est jamais ouvert en entier (`/core/ajax/update.php`) |
| ntfy (`ntfy.sylvain.cloud`) | `/`, `/uptime-kuma`, `/scripts`, `/github`, `/*/json`, `/*/ws`, `/*/auth` | appli ntfy du téléphone (abonnements) ; publieurs : Uptime Kuma, scripts des hôtes, CI GitHub, chacun sur son topic | comptes de ntfy : rien sans authentification (`auth-default-access: deny-all`), le téléphone sous le compte `sylvain`, chaque producteur avec un jeton en écriture seule sur son topic. L'interface web reste derrière le SSO |
| Paperless-ngx (`papiers.sylvain.cloud`) | `/share/*` | lien de partage d'un document | slug de 50 caractères aléatoires, expiration vérifiée par la vue. **Appli en pause** : ressource désactivée, rien ne répond |
| Promptoramix (`promptoramix.sylvain.cloud`) | `/*`, toute la ressource | fonctions edge Supabase du tournoi Linkx, sans plage d'IP fixe | signature HMAC de chaque POST (`LINKX_SECRET`) ; `/health` ne révèle rien. Seule ouverture d'une appli entière, assumée |
| TREK (`travels.sylvain.cloud`), OAuth du MCP | `/.well-known/oauth-protected-resource/mcp`, `/.well-known/oauth-protected-resource`, `/.well-known/oauth-authorization-server`, `/.well-known/oauth-authorization-server/mcp`, `/.well-known/openid-configuration`, `/mcp/.well-known/oauth-protected-resource`, `/mcp/.well-known/oauth-authorization-server`, `/mcp/.well-known/openid-configuration`, `/oauth/token` | serveurs des assistants (Claude.ai…) | documents de découverte statiques ; `/oauth/token` exige le code PKCE ou le jeton de rafraîchissement plus le secret du client, débit limité par TREK. Restent derrière le SSO : `/oauth/authorize`, `/oauth/consent`, `/oauth/register`, `/oauth/revoke`, `/oauth/userinfo` |
| TREK, partages | `/assets/*`, `/theme-boot.js`, `/shell-guard.js`, `/icons/icon.svg`, `/icons/icon-white.svg`, `/icons/apple-touch-icon-180x180.png`, `/shared/*`, `/api/shared/*`, `/public/journey/*`, `/api/public/journey/*`, `/uploads/covers/*`, `/uploads/places/*` | lien de partage d'un voyage, album de voyage | jeton de 24 octets aléatoires (voyage : 90 jours ; album : sans expiration, révoqué en le supprimant), vérifié à chaque requête. `/uploads/covers/*` et `/uploads/places/*` n'ont **aucun** jeton : le nom de fichier (UUID) suffit, et une URL déjà donnée répond encore après la révocation du partage |
| Wishlist (`cadeaux.sylvain.cloud`) | `/lists/*`, `/_app/*`, `/fonts/*`, `/api/assets/*`, `/api/users/public`, `/api/lists/*/items/*/claims` | la famille, par un lien de liste publique envoyé par message | liste publique (l'administrateur du groupe l'autorise), réservation refusée (404) sur une liste non publique ; `/lists/create` et la gestion des listes redirigent vers la connexion. Les images (`/api/assets/*`) sont servies sans contrôle : noms `<slug>-<horodatage>.webp`. `/api/users/public` crée un invité sans session ni accès |

## Chemins qui gardent l'authentification Pangolin (`PASS` + jeton d'accès)

Un `PASS` saute les règles pays mais laisse la requête aller à
l'authentification de Pangolin : une session SSO, ou un **jeton d'accès** de
la ressource (`pangolin_resource_access_token`), envoyé en en-têtes
`P-Access-Token-Id` / `P-Access-Token` ou dans l'URL (`?p_token=<id>.<jeton>`).

| Appli | Chemin | Client, jeton | Puis, côté appli |
|---|---|---|---|
| TREK | `/mcp` (exact, priorité 3) | assistants : jetons `claude-ai` (dans l'URL du connecteur, Claude.ai n'envoie pas d'en-tête) et `claude-code` (`tofu output -json trek_mcp_client_access_tokens`) | jeton OAuth de TREK. Depuis la maison aussi, le jeton Pangolin est exigé : le `PASS` passe avant l'`ACCEPT` de l'IP |
| Beszel (`monitoring.sylvain.cloud`) | `/api/beszel/agent-connect` (exact, priorité 3) | agents de Pangolin et de flip, un jeton par agent (`beszel_agent_hub_headers`) | jeton de l'agent (`X-Token`), puis son empreinte, figée à la première connexion. Les agents du LAN passent par le port publié sur la VM docker, pas par Pangolin |
| VictoriaLogs (`logs.sylvain.cloud`) | `/insert/jsonline` (exact, priorité 3) | agents Vector de Pangolin et de flip, un jeton par agent (`log_agent_access_tokens`) | compte vmauth de l'agent, en écriture seule sur ce chemin. Les agents du LAN passent par le port publié sur la VM docker, pas par Pangolin |

Sans règle de chemin, d'autres clients passent le SSO avec un jeton d'accès,
mais **restent soumis au filtre pays** (FR, DE et les pays de voyage) :

- Karakeep : appli mobile, extension du navigateur et serveur MCP, un jeton
  chacun (`tofu output -json karakeep_client_access_tokens`), puis la clé
  d'API de Karakeep. Toute l'API, tRPC compris, reste derrière le SSO et le
  filtre pays : en voyage hors de ces pays, l'appli mobile est refusée.
- Papra : appli mobile officielle, un jeton (`mobile`, lu avec
  `tofu output -json papra_client_access_tokens` dans `tofu/pangolin_config`).
  Dans l'appli (1.1.0 ou plus), écran du serveur : « Auto-hébergement »,
  serveur `https://papra.sylvain.cloud`, puis « En-têtes personnalisés »
  (« Custom headers » en anglais) `P-Access-Token-Id` et `P-Access-Token`
  avec les valeurs de la sortie ; ensuite le compte Papra. Aucun chemin ouvert : toute l'API
  reste derrière le SSO et le filtre pays.
- Grocy : l'appli Android (patzly/grocy-android) n'envoie pas d'en-tête
  personnalisé, donc pas de jeton d'accès. Elle passe par
  l'**authentification par en-tête** de Pangolin
  (`pangolin_resource_header_auth.grocy_mobile`, `website_grocy.tf`) :
  identifiants HTTP Basic écrits dans l'URL du serveur, que l'appli
  transforme en en-tête `Authorization: Basic`. URL lue avec
  `tofu output -raw grocy_mobile_server_url` dans `tofu/pangolin_config`
  (`https://mobile:<mot de passe>@grocy.sylvain.cloud`), à saisir comme
  serveur dans l'appli, puis une clé d'API de Grocy (Paramètres > Gérer les
  clés d'API). Aucun chemin ouvert : toute la ressource reste derrière le
  filtre pays, et les navigateurs gardent la page de connexion du SSO
  (`extended_compatibility = false`).
- Les sondes Uptime Kuma (`Healthcheck <appli>`) : un jeton par appli
  surveillée (`pangolin_resource_access_token.healthcheck`, `websites.tf`).

## Ressources sans SSO

Le test `every_public_resource_applies_its_rules` épingle ces deux-là comme
les seules. Les règles pays s'y appliquent quand même (`apply_rules = true`
partout).

| Ressource | Client | Ce qui protège |
|---|---|---|
| Betisier (`betisier.sylvain.dev`) | navigateur (appli de TP, publique) | l'appli elle-même ; FR et DE seulement |
| Promptoramix | serveurs du tournoi | HMAC ; et son `ACCEPT` de `/*` lève aussi le filtre pays |

## L'IP de la maison

`ACCEPT` de `home_ip` (clé de `secrets/secrets.sops.yaml`) en priorité 9 sur
Immich, Dawarich et TREK : depuis la connexion de la maison, toute la
ressource répond sans SSO, et sans le code PIN Pangolin d'Immich
(`pangolin_resource_pincode.immich`). C'est ce qui fait marcher l'appli
mobile d'Immich sur le Wi-Fi de la maison, et l'envoi de positions de
Dawarich (Overland, OwnTracks…), qui n'ouvre aucun chemin au monde. Dehors, rien
n'est déclaré pour l'appli mobile d'Immich : ni chemin ouvert, ni jeton
d'accès.

Ce que ça fait confiance : tout appareil derrière la box (Wi-Fi invité
compris), et l'adresse plutôt que la maison. Si l'opérateur réattribue l'IP,
le nouveau titulaire a le même accès jusqu'à ce que `home_ip` soit mis à jour
**et** `pangolin_config` appliqué (rien ne l'applique tout seul).

## Pays de voyage

En voyage, les ressources derrière le SSO refusent le pays (DROP 99) avant
même la page de connexion. Pour l'ouvrir : ajouter le pays et sa date de fin
à `travel_countries` (`tofu/pangolin_config/variables.tf`, code ISO en
majuscules, date RFC 3339 UTC), puis `tofu apply` dans
`tofu/pangolin_config`. Il prend la priorité 20 sur **toutes** les
ressources. Le premier apply après la date le referme, et le `check
"travel_countries_stale"` demande alors de retirer l'entrée. Rien n'applique
`pangolin_config` à heure fixe : le pays reste ouvert jusqu'au prochain apply
après la date. Aucun pays de voyage ouvert aujourd'hui.

Les `ACCEPT` de chemin n'en ont pas besoin, ils répondent déjà de partout.

## Verrouillage PHP (temporaire)

`tofu/pangolin_config/php_lockdown.tf`, en attendant qu'une faille critique
de PHP (publiée le 2026-10-21) soit corrigée dans les images :

- `php_lockdown_sso` force le SSO sur les ressources qu'il nomme. Vide
  aujourd'hui : Betisier et Nextcloud en sont sortis, leurs images sont
  corrigées ;
- `php_lockdown_path_bypasses` **désactive** (sans les supprimer) les
  `ACCEPT` de chemin des ressources qu'il nomme : Monica. La synchronisation
  CardDAV/CalDAV du téléphone avec Monica est coupée jusqu'à la levée.

Lever : vider les deux ensembles une fois les images corrigées déployées,
puis `tofu apply`.

## Avec le client Pangolin

Hors de ces règles publiques, le client Pangolin (appli mobile ou de bureau)
ouvre les ressources **privées** (`private_resources.tf`), à qui y a droit :
Jellyfin (`https://media.sylvain.cloud`, rôle `jellyfin`), l'interface du NAS
(`https://nas.sylvain.cloud:8443`), l'interface de la box
(`bbox-internal.sylvain.cloud`), celle de l'imprimante (`print.sylvain.cloud`)
et les accès d'administration (`pi.internal`, `docker-apps.internal`,
`pve.internal`, `flip.internal`).
Rien de tout ça n'est public. Voir [architecture.md](architecture.md).

## SSH depuis le téléphone (ConnectBot)

ConnectBot (Android) a sa propre clé, `keys/android.pub` (ED25519,
`SHA256:H6gtq2yQ…zow`), posée en exclusif par `00-setup.yaml` sur les hôtes
qu'il cible. Une fiche par hôte, utilisateur `sylvain`, port 22 :

| Fiche | Adresse | Dehors |
|---|---|---|
| pangolin | `pangolin.sylvain.cloud` | direct (IP publique) : le premier à ouvrir si le reste ne répond plus |
| docker | `docker-apps.internal` | client Pangolin (à la maison : `192.168.1.216`) |
| pi | `pi.internal` | client Pangolin (à la maison : `192.168.1.96`) |
| newt-lxc | `192.168.1.200` | à la maison seulement, client Pangolin coupé : sa ressource `dns.internal` route `192.168.1.200` par le tunnel en TCP 53 seul |
| flip | `flip.internal` | client Pangolin |

- `flip.internal` passe par le Newt de flip : depuis cette session, ne jamais
  redémarrer `newt` ni Docker, la connexion tomberait avec. Newt de flip en
  panne : le rebond par Pangolin depuis le poste (`mise run ssh_flip`), puis
  la console Hetzner ([runbooks/flip-injoignable.md](runbooks/flip-injoignable.md)).
- Le NAS (`nas.sylvain.cloud`, port 22) et Proxmox (`pve.internal`) n'ont pas
  la clé ConnectBot : `00-setup.yaml` ne les vise pas.
- Le sshd durci accepte ConnectBot (tableau des clients dans
  [runbooks/ssh-refuse-apres-durcissement.md](runbooks/ssh-refuse-apres-durcissement.md)).

## Ajouter une ouverture

Toujours la plus étroite possible : un chemin exact plutôt qu'un préfixe,
jamais une appli entière (Promptoramix est l'exception assumée).

1. **Lire les routes** dans les sources de l'appli, à la version épinglée
   par son compose : chaque chemin que le client appelle vraiment, et pour
   chacun la vérification que fait l'appli (jeton, signature, mot de passe).
   Ce qui ne vérifie rien n'est ouvert que s'il ne sert rien de privé.
2. **Déclarer** dans `website_<app>.tf` une
   `local.<app>_<usage>_paths = { "<chemin>" = <priorité> }`, priorité entre
   2 et 9 (des règles d'une même ressource à la même priorité doivent avoir
   la même action : test `tied_rules_share_their_action`), un commentaire par chemin avec la vérification de l'appli et la
   version lue. Un `*` final couvre aussi le chemin sans lui (`/mcp/*`
   couvre `/mcp`). Ajouter l'entrée à `local.path_bypasses` (`rules.tf`),
   clé = nom de la ressource Pangolin : la règle `path_bypass` et la garde
   antislash en découlent.
3. **Épingler la version relue** dans
   `tofu/pangolin_config/path_bypass_images.json` (`image`, `version`,
   `compose`, `paths`, `reread` : les sources à relire, `releases`). Une
   image à nous (planning-equipes, promptoramix) n'y va pas : elle s'ajoute
   aux exemptions du test `path_bypasses_follow_their_image`.
4. **Mettre à jour les tests** : la liste de
   `path_bypasses_open_exactly_the_reviewed_paths`, et, pour une appli PHP,
   l'état attendu de `php_lockdown_closes_every_public_php_path`. Puis
   `mise run tofu-test` (ou `tofu test` dans `tofu/pangolin_config`).
5. **PR**, puis `tofu plan` et `tofu apply` dans `tofu/pangolin_config` (pas
   `mise run plan`, qui vise `tofu/pangolin`) : c'est Sylvain qui applique.
   Mettre ce document à jour dans la même PR.

Un client qui doit garder l'authentification Pangolin (un serveur, un
agent) prend un `PASS` plutôt qu'un `ACCEPT` : une
`pangolin_resource_rule` à part avec son `pangolin_resource_access_token`,
ajoutée à `local.declared_extra_rules` et `local.standalone_path_rule_resources`
(`rules.tf`), sur le modèle de `trek_mcp` ou `beszel_agent_connect`. Un
`PASS` n'entre pas dans `path_bypass_images.json` : une route déplacée
couperait le client, elle n'ouvrirait rien.

**À chaque montée de version** d'une image de `path_bypass_images.json`,
Renovate monte le fichier en même temps que le compose (même `depName`), et
la PR ne fusionne jamais seule (`automerge: false` sur ce fichier, dernière
règle de `renovate.json`) ; une note dans sa description le rappelle. Avant
de merger, lire les notes de version (`releases`) et les sources listées
dans `reread` de l'entrée de l'appli ; si une route ouverte a bougé, corriger
les `_paths` de l'appli dans la même PR.
