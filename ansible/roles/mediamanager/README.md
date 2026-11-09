# Rôle `mediamanager`

MediaManager ([maxdorninger/MediaManager](https://github.com/maxdorninger/MediaManager),
image `master` du 05/07/2026, voir « Version ») **à l'essai** sur le NAS : on y demande un film ou une série,
Prowlarr cherche sur des trackers publics, qBittorrent télécharge par le VPN,
MediaManager range le fichier dans son propre dossier de `media`, que Jellyfin
lit par deux bibliothèques à lui : ta collection n'est jamais touchée. S'il ne convainc pas : skill
`remove-app` (plus bas, « Retirer l'essai »).

Partie de `nas.yml` (tag `mediamanager`), lancé à la main seulement, jamais
par la CI. Un projet Compose sous `dc@mediamanager` (unité système, comme
toutes les applis du NAS : `ansible/roles/docker_service/README.md`), dans
`/volume1/docker/mediamanager`.

## Ce qui tourne

| Service | Conteneur | Réseau | Rôle |
|---|---|---|---|
| `mediamanager` | `mediamanager` | `default`, `db`, `proxy` | l'appli, en `sylvain` (jamais root : lancé en root, son script ferait un `chown -R` de `/data`) |
| `db` | `mediamanager-db` | `db` (interne, sans sortie) | PostgreSQL 17 |
| `gluetun` | `mediamanager-gluetun` | `default`, `proxy` | tunnel WireGuard, kill switch ; `proxy` pour que le Traefik du NAS joigne Prowlarr et qBittorrent |
| `qbittorrent` | `mediamanager-qbittorrent` | celui de gluetun | téléchargements |
| `prowlarr` | `mediamanager-prowlarr` | celui de gluetun | indexeurs (trackers publics) |

gluetun, qBittorrent et Prowlarr ne sont **rendus dans le compose qu'avec une
clé WireGuard** (`mediamanager_wireguard_private_key`) : sans elle, rien qui
télécharge ou cherche n'existe, donc rien ne peut partir par la connexion de
la maison ; MediaManager démarre seul, qBittorrent et Prowlarr coupés dans sa
configuration. Retirer la clé et relancer le rôle les supprime
(`--remove-orphans` de `dc@`).

### Bac à sable et liens physiques

`/volume1/media/mediamanager/{films,series,torrents}` (caché, en
`.mediamanager-test`, jusqu'au premier import réussi le 07/11), au compte
`sylvain`, `0750`. Il est **dans** le dossier partagé `media`, parce que
chaque dossier partagé d'UGOS est un sous-volume btrfs à part (vérifié : `media`
et `docker` ont des `st_dev` différents) et qu'un lien physique ne traverse pas
un sous-volume : MediaManager retomberait alors sans rien dire sur une copie.
Il est hors des dossiers de la collection : Jellyfin, qui garde `media` en
lecture seule, le lit par deux bibliothèques à lui, créées à la main
(Tableau de bord → Bibliothèques → Ajouter) :

| Bibliothèque | Type | Dossier (vu par Jellyfin) |
|---|---|---|
| Nouveautés films | Films | `/media/mediamanager/films` |
| Nouveautés séries | Séries | `/media/mediamanager/series` |

**Migration depuis `.mediamanager-test`** (une fois, avant de relancer le rôle) :
le rôle ne déplace rien et créerait un dossier vide, alors que la base de
MediaManager et l'état de qBittorrent pointent sur des fichiers qui seraient
restés dans l'ancien dossier. Sur le NAS : `sudo systemctl stop dc@mediamanager`,
`sudo mv /volume1/media/.mediamanager-test /volume1/media/mediamanager`, puis
`nas.yml --tags mediamanager`.

Le dossier est en `0750` au compte `sylvain` : Jellyfin le lit parce qu'il
tourne sous le même compte (`jellyfin_user`, `1000:10`) ; le changer couperait
ces deux bibliothèques.

`torrents` n'est jamais une bibliothèque : il garde les noms du tracker et,
pour un film, le même fichier une seconde fois (lien physique).

MediaManager et qBittorrent montent ce dossier **une seule fois, en `/data`,
au même chemin** : un lien physique entre deux montages distincts échoue
(`EXDEV`), même sur le même système de fichiers. `torrent_directory` et
`category_save_path` valent `/data/torrents` des deux côtés.

Jamais `media/films` ni `media/series` dans MediaManager : l'import d'une
bibliothèque existante renomme chaque dossier importé avec un point devant
(`docs/importing-existing-media.md` de MediaManager), ce qui le ferait
disparaître de Jellyfin.

### VPN : gluetun, WireGuard et redirection de port

qBittorrent et Prowlarr n'ont **pas de réseau à eux** (`network_mode:
service:gluetun`) : tout ce qu'ils envoient passe par l'espace réseau de
gluetun, dont le pare-feu ne laisse sortir que par le tunnel (et vers le
réseau du projet). Tunnel tombé : plus rien ne sort. qBittorrent est en plus
lié à l'interface du tunnel (`Session\Interface=tun0`). Ils démarrent après
gluetun (`depends_on: service_started`, `restart: true`), sans attendre qu'il
soit sain : un VPN injoignable ferait sinon échouer le `compose up` de `dc@`,
qui arrêterait tout le projet en boucle. Rien ne fuit pour autant : le
pare-feu de gluetun bloque tout dès son démarrage, tunnel monté ou non.

**Redirection de port (défaut, ProtonVPN)** : `VPN_PORT_FORWARDING=on`, et
`PORT_FORWARD_ONLY=on` pour ne choisir que des serveurs P2P. ProtonVPN donne
un port entrant par NAT-PMP, différent à chaque connexion. gluetun le passe à
qBittorrent par le mécanisme qu'il documente
([vpn-port-forwarding](https://github.com/qdm12/gluetun-wiki/blob/main/setup/advanced/vpn-port-forwarding.md)) :
`VPN_PORT_FORWARDING_UP_COMMAND` appelle `POST /api/v2/app/setPreferences` de
qBittorrent sur le `127.0.0.1` qu'ils partagent (`listen_port`, interface,
`random_port` et UPnP coupés), `VPN_PORT_FORWARDING_DOWN_COMMAND` remet le port
à 0 quand la redirection tombe (un bug de qBittorrent exige de le reposer pour
que la redirection reprenne), sans toucher à l'interface : la doc de gluetun
bascule aussi sur `lo`, mais ProtonVPN refuse un renouvellement NAT-PMP toutes
les 2 à 5 minutes (vu le 07/11 sur deux serveurs, même port rendu 10 à 60 s
plus tard), et chaque bascule coupait tous les transferts. Rien ne fuit pour
autant : qBittorrent reste lié à `tun0`, et le pare-feu de gluetun bloque tout
hors du tunnel. Ces appels passent sans mot de passe parce que
`WebUI\LocalHostAuth=false` : seuls gluetun, qBittorrent et Prowlarr voient
cette boucle locale. MediaManager, lui, passe par `http://gluetun:8080` et se
connecte avec le compte `mediamanager`.

**AirVPN (alternative, port fixe)** : réserver un port dans l'espace client
d'AirVPN, générer une configuration WireGuard, puis, dans `host_vars/nas` :

```yaml
mediamanager_vpn_provider: airvpn
mediamanager_vpn_port_forwarding: false
mediamanager_vpn_static_port: 12345   # le port réservé
```

et les clés SOPS `mediamanager_wireguard_private_key`,
`mediamanager_wireguard_preshared_key`, `mediamanager_wireguard_addresses`
(adresse IPv4 seule si Docker n'a pas d'IPv6). Le port est ouvert dans le
pare-feu de gluetun (`FIREWALL_VPN_INPUT_PORTS`) et posé dans
`qBittorrent.conf` (`Session\Port`). Ce fichier n'est posé qu'une fois
(`force: false`) : sur une installation existante, régler le port dans
l'interface de qBittorrent, ou repartir du modèle (plus bas).

### Accès

- **MediaManager** : `https://mediamanager.sylvain.cloud` (ou `:8443`),
  exactement comme Jellyfin (`docs/architecture.md`) : servi par le Traefik
  du NAS (rôle `nas_proxy`, routeur `mediamanager`, certificat Let's Encrypt
  par DNS-01 OVH), qui joint le conteneur sur `mediamanager:8000` par le
  réseau Docker `proxy` du projet (`mediamanager_proxy`, interne, créé par
  `dc@nas_proxy` et rejoint ici en externe : `mediamanager` après `nas_proxy`
  dans `nas.yml` ; l'essai dépend du Traefik du NAS, jamais l'inverse). À la maison, le A public `tofu/dns/mediamanager.tf` vise l'IP
  LAN du NAS (laissé passer par Blocky, `blocky_rebinding_allowed_domains`) ;
  dehors, le client Pangolin résout le même nom vers la ressource privée
  `mediamanager` (site `nas`, `tofu/pangolin_config/private_resources.tf`,
  `nas-proxy` en TCP 443 et 8443), ouverte au rôle Pangolin `mediamanager`
  (y ajouter Sylvain seul, dans l'UI). Aucun port publié pour MediaManager,
  qui n'est plus sur `newt` ; la base n'est que sur `db`. **Pas une
  barrière** : le Traefik choisit l'appli au nom demandé, donc tout appareil
  du LAN et tout membre du rôle `jellyfin` (par l'alias
  `media.sylvain.cloud`) peut atteindre la page de connexion ; le compte de
  MediaManager est le seul verrou.
- **qBittorrent et Prowlarr** : `https://qbittorrent.sylvain.cloud` et
  `https://prowlarr.sylvain.cloud` (ou `:8443`), de la même façon que
  MediaManager (routeurs `qbittorrent` et `prowlarr` de `nas_proxy`, A publics
  de `tofu/dns/prowlarr.tf` et `qbittorrent.tf`, laissés passer par Blocky, ressources
  privées Pangolin `Prowlarr` et `qBittorrent` du site `nas`), mais ouvertes
  au seul rôle Pangolin **`mediamanager-admin`** (Sylvain, ajouté à ce rôle ou
  au groupe Pocket ID du même nom, dans l'UI), pas au rôle `mediamanager`.
  Ni l'un ni l'autre ne fait d'OIDC : le Traefik du NAS les met derrière
  Pocket ID avec oauth2-proxy (forwardAuth, rôle `nas_proxy`), qui exige le
  groupe `mediamanager-admin` sur tout chemin (LAN, 443, 8443, Pangolin) ; sans
  les sorties Tofu du client `mediamanager-tools`, rien n'est rendu et les
  routeurs restent comme avant. **Pocket ID seul** quand ce client existe
  (`mediamanager_ui_sso_only`) : Prowlarr en authentification `External` (aucun
  login), qBittorrent dispense de mot de passe le sous-réseau du réseau `proxy`
  (`bypass_auth_subnet_whitelist`, réglé par son API à chaque déploiement, le
  sous-réseau étant attribué par Docker). Sans le client, ou en secours (plus
  bas), chacun redemande son propre login. Le Traefik du NAS les joint par
  `http://mediamanager-gluetun:9696` et `:8080` : gluetun est aussi sur le
  réseau `proxy` (interne, sans passerelle). Le pare-feu de gluetun admet
  l'entrant vers le sous-réseau de chaque interface Ethernet locale et n'y
  laisse sortir que vers ce sous-réseau : le kill switch (sortie par le tunnel
  seul) est inchangé, et rien d'autre que le réseau `proxy` ne voit ces deux
  ports. `WebUI\LocalHostAuth=false` ne vaut que pour la boucle locale
  (`127.0.0.1` de l'espace réseau de gluetun) : la requête de Traefik arrive
  avec son IP de réseau `proxy`, et `ReverseProxySupportEnabled` reste à son
  défaut (faux), donc `X-Forwarded-For` n'est jamais cru et personne n'est pris
  pour `localhost` ; seul le sous-réseau du réseau `proxy` (Traefik, gluetun,
  MediaManager) est dispensé de mot de passe. Sans login aussi : Prowlarr
  (`External`) pour tout ce qui joint son port, soit le `127.0.0.1` du NAS
  (tunnel SSH ci-dessous, comptes du NAS) et les réseaux de la pile (`default`,
  `proxy`). Rien de cela n'est joignable depuis le LAN sans passer par Traefik,
  donc par Pocket ID. `nas.yml` déploie `nas_proxy` avant `mediamanager` :
  lancer `--tags mediamanager` seul quand l'oauth2-proxy n'est pas (encore)
  déployé ouvrirait les deux interfaces sans login au LAN, toujours
  `--tags nas_proxy,mediamanager`. Les défauts de
  qBittorrent suffisent derrière Traefik (`HostHeaderValidation` actif mais
  `ServerDomains=*`, Traefik garde l'en-tête `Host`, la vérification CSRF
  compare `Origin` et `Host`) : `qBittorrent.conf` n'est pas modifié. Repli,
  toujours là, les ports sur le `127.0.0.1` du NAS (jamais sur le LAN). Depuis
  le PC, à la maison (ou dehors, client Pangolin connecté, ressource `nas`) :

  ```bash
  ssh -N -L 8080:127.0.0.1:8080 -L 9696:127.0.0.1:9696 sylvain@192.168.1.137
  ```

  puis `http://localhost:8080` (qBittorrent) et `http://localhost:9696`
  (Prowlarr), sans login (boucle locale de qBittorrent, `External` de
  Prowlarr). C'est le premier secours quand Pocket ID ou oauth2-proxy
  (`nas-proxy-oauth2`) est en panne : ce chemin ne passe pas par Traefik, donc
  pas par la porte Pocket ID.

#### Login local de secours

Pour rouvrir `prowlarr.sylvain.cloud` et `qbittorrent.sylvain.cloud` avec le
login de chaque appli (Pocket ID durablement en panne, oauth2-proxy retiré, ou
pour tester sans lui) :

1. Dans `ansible/host_vars/nas/variables.yaml`, `mediamanager_local_login:
   true` (PR, ou à la main pour la durée de la panne : `-e
   mediamanager_local_login=true`).
2. `ansible-playbook nas.yml --tags mediamanager` (depuis `ansible/`) :
   Prowlarr repasse en `Forms` (redémarre), qBittorrent perd sa dispense par
   son API (sans redémarrer).
3. **Prowlarr** : `ssh -t sylvain@192.168.1.137 sudo prowlarr-user` crée ou
   change le compte (identifiant et mot de passe saisis sur le NAS ; Prowlarr
   n'en a aucun au départ et le formulaire n'en propose pas).
4. **qBittorrent** : compte `mediamanager`, mot de passe dérivé de
   `backup_passphrase`, lu sur le NAS :

   ```bash
   ssh sylvain@192.168.1.137 "sudo sed -n '/^\[torrents.qbittorrent\]/,/^\[/p' /volume1/docker/mediamanager/config/config.toml | grep '^password'"
   ```

5. Retour à Pocket ID seul : `mediamanager_local_login: false` (ou sans le
   `-e`), même commande. Le compte de Prowlarr reste dans sa base, inutilisé.

Si oauth2-proxy est retiré sans passer par là, les sorties Tofu du client
`mediamanager-tools` disparaissent avec lui et le rôle remet les logins tout
seul au déploiement suivant (`mediamanager_sso_proxy` faux).

### Secrets

Dérivés de `backup_passphrase` (aucune clé SOPS) : mot de passe de la base,
`token_secret` de MediaManager, mot de passe de l'interface de qBittorrent
(compte `mediamanager`, posé en PBKDF2 dans `qBittorrent.conf`), clé d'API de
Prowlarr (`PROWLARR__AUTH__APIKEY`, la même dans `config.toml`). Pour les
lire, sur le NAS : `sudo grep -E 'password|api_key'
/volume1/docker/mediamanager/config/config.toml`.

**Rotation de `backup_passphrase`** : `config.toml` et Prowlarr suivent au
déploiement suivant, pas la base ni qBittorrent. PostgreSQL ne lit
`POSTGRES_PASSWORD` qu'à l'initdb : `ALTER USER` d'abord
(`docs/runbooks/mot-de-passe-base.md`). `qBittorrent.conf` n'est posé
qu'une fois : en repartir (« Repartir du modèle de qBittorrent », plus bas),
sinon MediaManager ne se connecte plus à qBittorrent.

Clés SOPS **facultatives**, posées par Sylvain (préfixe `mediamanager_wireguard_*`,
jamais le nom d'une variable du rôle ; chacune avec son entrée dans
`secrets/secrets-rotation.yaml`) :

| Clé | Quand |
|---|---|
| `mediamanager_wireguard_private_key` | toujours : sans elle, pas de VPN, pas de téléchargement |
| `mediamanager_wireguard_addresses` | AirVPN (ProtonVPN n'en a pas besoin) |
| `mediamanager_wireguard_preshared_key` | AirVPN |

Le pays des serveurs n'est pas un secret : `mediamanager_vpn_server_countries`
dans `host_vars/nas` (noms anglais de gluetun, « Switzerland,Netherlands »).

**Rotation de la clé WireGuard** (`kind: provider`, chaque année) : chez
ProtonVPN, le certificat lié à la clé expire au bout d'un an (date sur la page
WireGuard du compte). Expiré, le tunnel ne monte plus : rien ne fuit, mais
aucun moniteur ne le signale. Le prolonger (« Extend ») ou générer une autre
clé (« NAT-PMP (Port Forwarding) » coché), `sops set`, `nas.yml --tags
mediamanager`, puis `last_rotated` à la date du jour et `estimated: false`.

### Limites

Provisoires, celles de l'évaluation : MediaManager 512 Mo, PostgreSQL 256 Mo
(`mem_reservation` 128 Mo), qBittorrent 1 Go avec `cpus: 2.00` et
`cpu_shares: 512` (job par lots), Prowlarr 256 Mo, gluetun 256 Mo (remesuré le 2026-11-09 : pic de 118 Mio
pour 128). **Les autres, à
remesurer** après une semaine d'essai (`memory.peak` de chaque conteneur,
`docs/conventions/resource-limits.md`) et à recaler à ~2x le pic.

### Sauvegarde

Gabarit partagé (`borgmatic`, `tasks_from: app.yml`), borgmatic en conteneur
du NAS (02:30) : `config/` (dont `config.toml`), `qbittorrent/`, `prowlarr/`
(ses bases SQLite copiées par `sqlite3`, copie vivante exclue ; ni ses
journaux ni ses sauvegardes internes) et le compose, dans le dépôt
`backup/nas/mediamanager` de la Storage Box. Ni le bac à sable, ni les
affiches (`images/`), ni le dossier de PostgreSQL.

**La base PostgreSQL** est archivée en dump, `db-dump/mediamanager.dump`
(`pg_dump -Fc`, ~100 Ko le 08/11/2026). Le gabarit dumpe une base par
`docker exec <conteneur> pg_dump`, et le conteneur borgmatic du NAS n'a ni
CLI ni socket Docker (`tasks/app.yml` du rôle borgmatic refuse toute
`borgmatic_app_postgresql_databases` en mode conteneur) : c'est l'hôte qui
dumpe, par un drop-in de `borgmatic.service`
(`/etc/systemd/system/borgmatic.service.d/mediamanager-pgdump.conf`,
`ExecStartPre=-`, qui attend jusqu'à 5 min que la base réponde : rattrapage
au boot), juste avant le run de 02:30. Un dump raté ne bloque pas
les autres applis du NAS ; le hook `before` de `mediamanager.yaml` refuse un
dump de plus de 12 h, donc seule la sauvegarde de MediaManager échoue (au
journal de `borgmatic.service`, pas de moniteur). Le dossier `postgres/`
(copie vivante) n'est jamais archivé. `mediamanager_backup_enabled: false`
retire le drop-in ; `decommission_app` ne le connaît pas : l'effacer avec
l'appli (sinon son `docker exec` échoue, sans effet, chaque nuit).

Restauration, base vide recréée par le compose :

```bash
# dump extrait de l'archive (borgmatic extract), puis sur le NAS :
docker exec -i mediamanager-db pg_restore -U mediamanager -d mediamanager --clean --if-exists < mediamanager.dump
```

Pas de moniteur « Backup MediaManager » ni de test de restauration pour un
essai.

## Premier démarrage

1. `tofu/dns` et `tofu/pangolin_config` appliqués (A, ressource
   `mediamanager`, rôle, liaison), puis Sylvain ajouté au rôle `mediamanager`
   dans l'UI de Pangolin.
2. `ansible-playbook nas.yml --tags nas_proxy,mediamanager` (depuis
   `ansible/` ; `nas.yml` passe `nas_proxy`, qui crée le réseau
   `mediamanager_proxy`, avant `mediamanager`, qui le rejoint. Lancé seul
   avant `nas_proxy`, `dc@mediamanager` réessaierait toutes les 15 s sans
   rien casser d'autre).
3. `https://mediamanager.sylvain.cloud` (client Pangolin connecté, dehors) : le compte
   à l'adresse de `pangolin_le_email` (`mediamanager_admin_email`), mot de
   passe **`admin`**, créé au premier démarrage : **le changer aussitôt**.
4. Avec la clé WireGuard posée et le rôle relancé : `https://prowlarr.sylvain.cloud`
   (ou le tunnel SSH, plus haut),
   se connecter avec le compte créé par `ssh -t sylvain@192.168.1.137 sudo
   prowlarr-user` (Prowlarr n'en a aucun au départ et ne propose pas d'en
   créer : le formulaire est imposé par le compose ; le même script change le
   mot de passe) ; y ajouter des
   indexeurs publics, en laissant **« Redirect » décoché** sur chacun :
   Prowlarr télécharge alors lui-même le `.torrent` (par le VPN) au lieu de
   renvoyer MediaManager vers le tracker, qui le chercherait par la connexion
   de la maison.
5. Puis relancer `nas.yml --tags mediamanager` une fois : la sauvegarde ne
   copie par `sqlite3` que les bases trouvées au déploiement, et celles de
   Prowlarr n'existent pas encore au passage qui l'installe. D'ici là, elles
   ne sont pas sauvegardées (`prowlarr/*.db*` exclu, jamais de copie vivante).

## Contrôles

### Fuite du VPN

L'IP vue de l'extérieur depuis l'espace réseau de qBittorrent doit être celle
du VPN, jamais celle de la box :

```bash
# sur le NAS
sudo docker exec mediamanager-qbittorrent curl -s https://ifconfig.io   # IP du VPN
curl -s https://ifconfig.io                                             # IP de la maison, différente
sudo docker logs mediamanager-gluetun 2>&1 | grep -i -E "public ip|port forward"
```

Kill switch : `sudo docker exec mediamanager-gluetun ip link set tun0 down`
(ou couper le serveur), puis le même `curl` dans qBittorrent doit **échouer**
(délai dépassé), jamais répondre l'IP de la maison ; `sudo systemctl restart
dc@mediamanager` pour revenir.

Port redirigé : `sudo docker logs mediamanager-gluetun 2>&1 | grep -i
"port forwarded"` donne le port, que qBittorrent doit montrer dans Options →
Connexion (« Port pour les connexions entrantes »), et l'icône de connexion en
bas de l'interface doit être verte après quelques minutes de téléchargement.

### Liens physiques

Après l'import d'un film téléchargé, le fichier rangé et celui du dossier des
torrents sont un seul fichier, avec deux noms :

```bash
# sur le NAS
stat -c '%h %i %n' "/volume1/media/mediamanager/films/<Titre (année)>/"*.mkv \
  "/volume1/media/mediamanager/torrents/<nom du torrent>/"*.mkv
```

attendu : `2` (nombre de liens) et le **même numéro d'inode** sur les deux
lignes. `1` : MediaManager a copié (montages différents, ou dossier hors du
sous-volume `media`), l'espace est compté deux fois.

### Procédure d'essai

1. Demander un film libre de droits connu des trackers publics (Big Buck Bunny,
   Sintel) dans MediaManager, le laisser chercher, choisir un résultat.
2. Suivre le téléchargement dans qBittorrent (catégorie `MediaManager`,
   enregistré dans `/data/torrents`).
3. À la fin, MediaManager importe : contrôle des liens physiques (plus haut).
4. Même chose pour un épisode de série.
5. Une semaine plus tard : mémoire de chaque conteneur (`memory.peak`), limites
   à recaler ; décider si MediaManager reste.

## Repartir du modèle de qBittorrent

`qBittorrent.conf` n'est posé que s'il manque (qBittorrent le réécrit en
s'arrêtant). Pour revenir au modèle du rôle :

```bash
sudo systemctl stop dc@mediamanager
sudo rm /volume1/docker/mediamanager/qbittorrent/qBittorrent/qBittorrent.conf
# puis, depuis ansible/ sur le PC
ansible-playbook nas.yml --tags mediamanager
```

## Retirer l'essai

Skill `remove-app`, avec `nas.yml` :

```bash
cd ansible
ansible-playbook nas.yml --tags decommission \
  -e decommission_app_confirm=true \
  -e decommission_app_service=mediamanager \
  -e decommission_app_base_path=/volume1/docker/mediamanager \
  -e decommission_app_destroy_remote_backup=true
```

Le bac à sable est hors de `docker_base_path` et `decommission_app` n'efface
rien dans `media` (il n'accepte que `/mnt/nas/apps/<service>` en plus) : sur le
NAS, garder d'abord ce qui doit l'être (déplacer un film vers `media/films`
garde le fichier, le lien du dossier des torrents disparaît avec le reste),
puis `sudo rm -rf /volume1/media/mediamanager`.

Puis, dans le dépôt : ce rôle, `ansible/molecule/mediamanager/`, l'entrée de
`nas.yml`, dans `nas_proxy` le routeur, le service et les en-têtes
`mediamanager` (`templates/dynamic.yml`), le réseau `mediamanager` du compose,
les `nas_proxy_mediamanager_*`, `nas_proxy_prowlarr_*` et `nas_proxy_qbittorrent_*`
(routeurs, services, noms de `nas_proxy_cert_check_names`) et
l'entrée `mediamanager` de `nas_proxy_health_checks` (et leurs assertions dans
`ansible/molecule/nas_proxy/`) (puis `--tags nas_proxy` ; le réseau
`mediamanager_proxy`, vide, reste dans Docker : `docker network rm
mediamanager_proxy` ; le moniteur « Healthcheck NAS » reste, un seul pour
toutes les applis), les A `tofu/dns/mediamanager.tf`, `prowlarr.tf` et `qbittorrent.tf` et leur test,
`mediamanager.`, `prowlarr.` et `qbittorrent.sylvain.cloud` de
`blocky_rebinding_allowed_domains`, les ressources, les rôles (`mediamanager`,
`mediamanager-admin`) et les liaisons de
`tofu/pangolin_config/private_resources.tf` (et les deux rôles dans
`access_inventory.tf` et `pocket_id.tf`, leur test dans
`tests/invariants.tftest.hcl`), le réseau `proxy` de gluetun dans `compose.yaml`,
les clés SOPS `mediamanager_wireguard_*` et leurs entrées de rotation,
`docs/apps.md`, `docs/conventions/ansible.md`, `AGENTS.md` ; puis
`grep -rn mediamanager` sur tout le dépôt.

## Connexion par Pocket ID

Client `mediamanager` de `tofu/pangolin_config/pocket_id.tf` (groupe
`mediamanager`). Les `mediamanager_oidc_*` de `defaults/main.yml` lisent les
sorties Tofu ; tant qu'elles manquent, `[auth.openid_connect]` reste coupé.
Déploiement à la main (`nas.yml --tags mediamanager`). Pas de PKCE
(httpx-oauth). MediaManager lie par e-mail sans regarder `email_verified`.
Depuis l'image `master` (07/11, voir « Version »), `registration_enabled = false`
: ni la page d'inscription ni OIDC ne créent de compte, un membre du groupe
Pocket ID sans compte est refusé ; un admin l'ajoute dans Settings → Users
(mot de passe vide pour un compte OIDC seul, lié par e-mail). Admin :
l'adresse de `mediamanager_admin_email`.
Le rappel est bâti depuis la requête : `FORWARDED_ALLOW_IPS: "*"` fait croire
à uvicorn le `X-Forwarded-Proto` de nas-proxy (joint seulement par lui), et les
deux origines (443, 8443) sont déclarées. Le mot de passe reste.

## Version

Image `master` épinglée par digest (commit `98f2532`, 05/07/2026), pas une
version : la 1.12.3, dernière sortie, prend la réponse JSON de qBittorrent 5
(`TorrentsAddedMetadata`, `pending_count`) à l'ajout d'un torrent pour un échec
(#547, corrigé par #558), lève `API-Answer isn't 'Ok.'` et n'enregistre rien :
le torrent se télécharge mais n'est jamais importé (vu le 07/11). Le passage
fait 4 migrations de base (dont la suppression des « requests ») : pas de
retour à la 1.12.3 sans repartir d'une base vide. Revenir à une version
semver dès la suivante.
