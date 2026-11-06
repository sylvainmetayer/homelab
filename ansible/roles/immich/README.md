# immich

Immich sur le Raspberry Pi (`pi.yml`), avec des outils qui s'en servent :
Immich Swipe, Immich Kiosk, Immich Power Tools et Immich Selfie Timelapse (`docs/apps.md`).

## Immich Kiosk (`kiosk.sylvain.cloud`)

Cadre photo plein écran de [damongolding/immich-kiosk](https://github.com/damongolding/immich-kiosk),
image `ghcr.io/damongolding/immich-kiosk:0.45.2` (binaire Go, distroless,
utilisateur `nonroot`). Dans ce rôle et pas dans un rôle à part : comme Swipe,
il appelle `immich-server` par le réseau `immich` du projet compose, et
Immich reste sur le Pi ([ADR 0020](../../../docs/adr/0020-garder-le-raspberry-pi-pour-immich.md)).

**Rendu seulement si la clé SOPS `immich_kiosk_api_key` existe**
(`immich_kiosk_enabled`, dérivée, comme `immich_swipe_preconfigured`). La clé
est dans le `compose.yaml` (`0600`, `diff: false`), en `KIOSK_IMMICH_API_KEY`.
Retirer la clé ne supprime pas le conteneur : `docker compose up -d
--remove-orphans` dans `immich/`, ou `docker rm -f immich-kiosk`.

Clé : compte de Sylvain, Account Settings → API Keys, nom `immich-kiosk`,
**lecture seule**. Permissions (doc amont, « Installation »), sans les
boutons « j'aime » et « masquer » : `asset.read`, `asset.view`,
`asset.download`, `album.read`, `album.statistics`, `archive.read`,
`face.read`, `memory.read`, `person.read`, `person.statistics`,
`server.about`, `tag.read`, `user.read`. Ni `asset.update` ni aucune
permission `create`, `update` ou `delete` : à vérifier en créant la clé (les
noms exacts viennent de la doc amont, non essayés contre cet Immich). Rotation :
`docs/runbooks/rotation-des-secrets.md`.

Réglages : `KIOSK_BEHIND_PROXY=true`, `KIOSK_DISABLE_CONFIG_ENDPOINT=true`
(sinon `/config` rendrait la configuration, clé comprise). Pas de volume, pas de
port publié, pas de sauvegarde. Rôle Pangolin `immich-kiosk` sans membre
(administrateurs seulement), un test d'invariant de `pangolin_config` le garde
lié à cette seule ressource.

`mem_limit: 256m` est une valeur prudente, **à remesurer** sur le Pi.

**La TV de la maison.** Elle ne peut pas passer le SSO : l'adresse de la maison
l'évite (`immich_kiosk_home_ip`, `tofu/pangolin_config/website_immich_kiosk.tf`).
Tout appareil derrière cette adresse, Wi-Fi invité compris, voit donc le cadre
photo sans connexion. Hors de la maison, le SSO reste exigé. Si l'IP de la ligne
change, mettre à jour `home_ip` et appliquer `pangolin_config`.

## Immich Power Tools (`power-tools.sylvain.cloud`)

[immich-power-tools](https://github.com/immich-power-tools/immich-power-tools)
(AGPL-3.0, Next.js, image `ghcr.io/immich-power-tools/immich-power-tools:0.25.0`
épinglée par digest, arm64 compris ; la 0.25.0 date du 2026-10-05, Immich 3
exigé depuis la 0.22). Gestion en masse : personnes (fusion, suggestions),
lieux manquants, décalage de dates, albums potentiels, analyses, recherche.

**Connexion par Immich, sans clé d'API** (depuis le 2026-11-06). Avec
`IMMICH_API_KEY`, tout visiteur sans cookie était traité comme le propriétaire
de la clé (`getCurrentUser`, `user.utils.ts`) et `/api/immich-proxy/*`
relayait n'importe quel appel à l'API avec elle. La clé est retirée : le bouton
« Se connecter avec Pocket ID » (`OAUTH_ENABLED`) passe par l'OAuth d'Immich
(`/api/oauth/authorize`, appelé côté serveur sur `EXTERNAL_IMMICH_URL`, joint
depuis le Pi par l'IP de la maison), le rappel
`https://power-tools.sylvain.cloud/api/auth/oauth/callback` est déclaré sur le
client `immich` de Pocket ID, et le cookie de session porte le jeton Immich de
la personne. Sans cookie, les routes protégées échouent fermées. Les requêtes
directes à la base d'Immich (compte `postgres`, lecture) filtrent sur
l'utilisateur connecté, sauf `albums/[id]/public-info` (sans authentification)
et `albums/[id]/assets` (sans contrôle d'appartenance) : qui connaît l'UUID
d'un album en lit les métadonnées, pas les photos (elles passent par le proxy,
donc par les droits Immich). Lu dans le code de la 0.25.0, non essayé.

**Accès** : rôle Pangolin `immich-power-tools`, donné par le groupe Pocket ID
du même nom (le foyer). Le jeton d'accès du healthcheck (`websites.tf`)
franchit le SSO mais ne donne plus aucun droit sur la photothèque : sans
session Immich, l'appli n'agit pas.

**Accès direct à la base d'Immich.** L'appli se connecte à PostgreSQL
(`immich_postgres:5432`, réseau `immich`, base `immich`) avec les identifiants
d'Immich lui-même : utilisateur `postgres`, mot de passe `immich_db_password`
(posé dans le `compose.yaml`, `0600`). Lu dans les sources (0.25.0) :

- **lit** (`SELECT` par drizzle et SQL brut, pour les analyses, la carte
  thermique, les lieux manquants, les albums potentiels, les visages
  similaires) : assets, exif, personnes et visages, albums, et tout ce que le
  compte `postgres` voit, dont les hachages des mots de passe et des clés
  d'API d'Immich, les sessions et les liens de partage ;
- **n'écrit pas** : aucun `INSERT`, `UPDATE`, `DELETE` ni DDL contre cette base
  dans le code (recherche de `db.insert|update|delete` et de SQL d'écriture :
  rien) ; toutes les modifications de la photothèque passent par l'API d'Immich
  avec la clé ;
- **écrit** seulement dans son propre SQLite (`/app/data`, workflows, imports,
  réglages), jamais dans la base d'Immich.

Un compte `postgres` donne pourtant à l'appli le droit d'écrire et de lire tout
le serveur PostgreSQL : un défaut ou une compromission de l'appli ouvrirait la
base d'Immich en entier. Un rôle PostgreSQL en lecture seule dédié
(`GRANT SELECT`) réduirait cela ; non fait, il demande une étape Ansible qui
s'exécute dans `immich_postgres` après son démarrage, non testable ici.

Pas de `JWT_SECRET` : sans lui, les liens de partage publics de l'appli
(`/api/share-link/*`, qui se passent de session) ne peuvent pas être générés.
Aucune clé Google Maps ni de fournisseur d'IA (`AI_*`) : la carte thermique et
la recherche en langage naturel ne servent pas.

Durcissement : l'utilisateur `nextjs` (uid 1001, `USER` de l'image),
`read_only`, `cap_drop: ALL`, `no-new-privileges`, `tmpfs` sur `/tmp` et
`/app/data` (SQLite de l'appli : workflows, imports et réglages se perdent à un
redémarrage, rien n'est sauvegardé ; `mode=1777` plutôt que `uid=1001`, que
podman refuse). Essayé en local (podman, mêmes options) : démarre
(« Ready in 283ms »), `GET /api/health` répond `{"status":"healthy"}` (sans
appel à la base), `/` répond 200 ; **non essayé** : une session contre un vrai
Immich et sa base. `mem_limit` :
512m (~93 Mio mesurés au repos), à remesurer sur le Pi (`mem_report`).
Pas de volume, pas de port publié, pas de sauvegarde.

## Immich Swipe (`swipe-photos.sylvain.cloud`)

SPA statique (nginx) de [dev-nick421/immich-swipe](https://github.com/dev-nick421/immich-swipe),
image `ghcr.io/sylvainmetayer/immich-swipe:sha-a9644ff` (build ARM64). Le
navigateur appelle l'API d'Immich lui-même : `<URL du serveur>/api/...` avec
l'en-tête `x-api-key`.

**Préconfigurée par Ansible** quand la clé SOPS `immich_swipe_api_key` existe :
le rôle templatise `immich-swipe.conf` (`0600`, `diff: false`), monté à la
place du `default.conf` de l'image. Ce nginx :

- passe `/api/` à `immich-server:2283` par le réseau `immich` et y pose la
  vraie clé (`x-api-key`), en retirant `Cookie` et `Authorization` ;
- injecte dans `index.html` un script qui enregistre la configuration que
  l'écran de connexion aurait saisie (`localStorage` `immich-swipe-config`) :
  serveur = l'origine de la page (`https://swipe-photos.sylvain.cloud`), clé =
  un leurre (`server-side`) que nginx remplace ;
- renvoie `/photos/<id>` (« Ouvrir dans Immich ») vers l'Immich public (`immich_domain`) ;
- traduit le mode aléatoire pour Immich v3 (ci-dessous).

Pourquoi ce mode et pas les autres :

- **Variables `VITE_*` de l'amont** (`VITE_SERVER_URL`, `VITE_USER_1_*`) : lues
  à la construction de l'image seulement, et compilées dans le JavaScript
  servi ; la clé finirait dans une image publique de ghcr.io.
- **Appel direct de `photos.sylvain.cloud`** : CORS à ajouter sur la
  ressource Pangolin d'Immich (que Pangolin ne sait pas poser,
  fosrl/pangolin#2369), et la requête préliminaire `OPTIONS` d'un autre site
  part sans le cookie du SSO de Pangolin. La clé serait aussi dans le
  navigateur.
- **Proxy `/immich-api/` de l'image** : inutilisé par l'appli (elle appelle
  `/api/`), et il suit l'en-tête `X-Target-Host` vers n'importe quel hôte ;
  le `default.conf` remplacé ne l'a plus.

Ainsi : même origine (pas de CORS, le cookie du SSO de `swipe-photos` suffit),
clé jamais envoyée au navigateur, rien à changer sur Immich ni dans Pangolin.

**Qui l'utilise agit avec la clé de Sylvain.** La route `swipe-photos` a donc
son propre rôle Pangolin, `immich-swipe`
(`tofu/pangolin_config/website_immich_swipe.tf`), et non celui d'Immich : un
membre du rôle `immich` n'y entre pas d'office, il trierait (et mettrait à la
corbeille) la photothèque de Sylvain. Comme `immich-selfie-timelapse`, Tofu
crée le rôle sans membre : Sylvain s'y ajoute dans l'interface de Pangolin
(rôles de son utilisateur dans l'organisation). Un test d'invariant de
`pangolin_config` garde Swipe lié à ce seul rôle.

Clé : compte de Sylvain, Account Settings → API Keys, nom `immich-swipe`,
permissions `user.read`, `asset.read`, `asset.view`, `asset.download`,
`asset.update` (favori), `asset.delete` (corbeille, et l'annulation, que
`POST /trash/restore/assets` range sous `asset.delete`), `album.read`,
`albumAsset.create` (ajout à un album). Rotation :
`docs/runbooks/rotation-des-secrets.md` (« Secret d'appli lu par Ansible »).

Sans la clé (absente ou vide) : l'image telle quelle, URL et clé saisies
dans l'écran de connexion de l'appli, et le rôle supprime `immich-swipe.conf`.
Un navigateur déjà passé par le mode préconfiguré garde la configuration
injectée (serveur = `swipe-photos`, clé = le leurre) et n'affiche plus que
des erreurs : s'y déconnecter dans l'appli pour retrouver l'écran de connexion.

**Mode aléatoire.** L'appli (`useImmich.ts`, `fetchRandomAsset`) appelle
`GET /api/assets/random?count=N` (N = 5, ou 10 quand elle saute les vidéos),
qu'Immich v3 n'a plus : 400 « Validation failed ». Le nginx le réécrit en
`POST /api/search/random` avec le corps `{"size": N}` plus le filtre de
l'ancien endpoint (`withExif`, visibilité `archive` ou `timeline`, hors
corbeille) : `{"size": N}` seul renverrait les assets sans exif, et la vidéo
cachée (`hidden`) des photos animées, que l'appli montrerait seule et
pourrait mettre à la corbeille. L'appli écarte elle-même les vidéos et les
photos déjà vues. N passe par une `map` : `count` de 1 à 100 tel quel,
plafonné à 100 au-delà, 20 sinon ; seul un nombre entre dans le JSON. Même
clé et mêmes en-têtes retirés que `/api/`. Forme `filter` (Immich ≥ 3.2,
`search.dto.ts`) : à revoir si une montée d'Immich la change.
Seulement en mode préconfiguré (sans la clé, l'image d'origine garde l'appel
cassé). Le vrai correctif irait dans l'appli : appeler `/search/random` dans
le fork `sylvainmetayer/immich-swipe`, puis retirer ce `location`.
