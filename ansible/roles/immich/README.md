# immich

Immich sur le Raspberry Pi (`pi.yml`), avec deux outils qui s'en servent :
Immich Swipe et Immich Selfie Timelapse (`docs/apps.md`).

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
