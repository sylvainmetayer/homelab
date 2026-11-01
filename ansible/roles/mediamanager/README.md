# Rôle `mediamanager`

MediaManager ([maxdorninger/MediaManager](https://github.com/maxdorninger/MediaManager),
1.12.3) **à l'essai** sur le NAS : on y demande un film ou une série,
Prowlarr cherche sur des trackers publics, qBittorrent télécharge par le VPN,
MediaManager range le fichier. Tout se passe dans un bac à sable : les
bibliothèques de Jellyfin ne sont jamais touchées. S'il ne convainc pas : skill
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
| `gluetun` | `mediamanager-gluetun` | `default` | tunnel WireGuard, kill switch |
| `qbittorrent` | `mediamanager-qbittorrent` | celui de gluetun | téléchargements |
| `prowlarr` | `mediamanager-prowlarr` | celui de gluetun | indexeurs (trackers publics) |

gluetun, qBittorrent et Prowlarr ne sont **rendus dans le compose qu'avec une
clé WireGuard** (`mediamanager_wireguard_private_key`) : sans elle, rien qui
télécharge ou cherche n'existe, donc rien ne peut partir par la connexion de
la maison ; MediaManager démarre seul, qBittorrent et Prowlarr coupés dans sa
configuration. Retirer la clé et relancer le rôle les supprime
(`--remove-orphans` de `dc@`).

### Bac à sable et liens physiques

`/volume1/media/.mediamanager-test/{films,series,torrents}`, au compte
`sylvain`, `0750`. Il est **dans** le dossier partagé `media`, parce que
chaque dossier partagé d'UGOS est un sous-volume btrfs à part (vérifié : `media`
et `docker` ont des `st_dev` différents) et qu'un lien physique ne traverse pas
un sous-volume : MediaManager retomberait alors sans rien dire sur une copie.
Il est caché et hors des dossiers des bibliothèques : Jellyfin, qui garde
`media` en lecture seule, ne le voit pas.

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
à 0 quand le tunnel tombe (un bug de qBittorrent exige de le reposer pour que
la redirection reprenne). Ces appels passent sans mot de passe parce que
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
- **qBittorrent et Prowlarr** : publiés sur le `127.0.0.1` du NAS seulement
  (ports 8080 et 9696, sur gluetun), jamais sur le LAN ni par Pangolin. Depuis
  le PC, à la maison (ou dehors, client Pangolin connecté, ressource `nas`) :

  ```bash
  ssh -N -L 8080:127.0.0.1:8080 -L 9696:127.0.0.1:9696 sylvain@192.168.1.137
  ```

  puis `http://localhost:8080` (qBittorrent, compte `mediamanager`) et
  `http://localhost:9696` (Prowlarr).

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

### Limites

Provisoires, celles de l'évaluation : MediaManager 512 Mo, PostgreSQL 256 Mo
(`mem_reservation` 128 Mo), qBittorrent 1 Go avec `cpus: 2.00` et
`cpu_shares: 512` (job par lots), Prowlarr 256 Mo, gluetun 128 Mo. **À
remesurer** après une semaine d'essai (`memory.peak` de chaque conteneur,
`docs/conventions/resource-limits.md`) et à recaler à ~2x le pic.

### Sauvegarde

Gabarit partagé (`borgmatic`, `tasks_from: app.yml`), borgmatic en conteneur
du NAS (02:30) : `config/` (dont `config.toml`), `qbittorrent/`, `prowlarr/`
(ses bases SQLite copiées par `sqlite3`, copie vivante exclue ; ni ses
journaux ni ses sauvegardes internes) et le compose, dans le dépôt
`backup/nas/mediamanager` de la Storage Box. Ni le bac à sable, ni les
affiches (`images/`), ni le dossier de PostgreSQL.

**La base PostgreSQL de MediaManager n'est pas sauvegardée.** Le gabarit
dumpe une base par `docker exec <conteneur> pg_dump`, et le conteneur
borgmatic du NAS n'a ni CLI ni socket Docker : `tasks/app.yml` du rôle
borgmatic refuse toute `borgmatic_app_postgresql_databases` en mode conteneur.
Vérifié le 01/11/2026 : l'image borgmatic (2.1.10, Alpine) a `pg_dump` 18.6
mais pas `docker` ; le `docker` d'UGOS est lié à la glibc et ne tournerait pas
dans cette image ; le conteneur borgmatic est sur le pont par défaut, sans
accès au réseau `db` du projet. Les options sont dans la PR ; d'ici là, une
restauration repart d'une base vide (MediaManager recrée son schéma) avec la
configuration restaurée. Pas de moniteur « Backup MediaManager » ni de test de
restauration pour un essai.

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
4. Avec la clé WireGuard posée et le rôle relancé : tunnel SSH (plus haut),
   Prowlarr demande de créer son compte à la première visite ; y ajouter des
   indexeurs publics, en laissant **« Redirect » décoché** sur chacun :
   Prowlarr télécharge alors lui-même le `.torrent` (par le VPN) au lieu de
   renvoyer MediaManager vers le tracker, qui le chercherait par la connexion
   de la maison.

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
stat -c '%h %i %n' "/volume1/media/.mediamanager-test/films/<Titre (année)>/"*.mkv \
  "/volume1/media/.mediamanager-test/torrents/<nom du torrent>/"*.mkv
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
puis `sudo rm -rf /volume1/media/.mediamanager-test`.

Puis, dans le dépôt : ce rôle, `ansible/molecule/mediamanager/`, l'entrée de
`nas.yml`, dans `nas_proxy` le routeur, le service et les en-têtes
`mediamanager` (`templates/dynamic.yml`), le réseau `mediamanager` du compose,
les `nas_proxy_mediamanager_*` et le nom de `nas_proxy_cert_check_names` (puis
`--tags nas_proxy` ; le réseau `mediamanager_proxy`, vide, reste dans Docker :
`docker network rm mediamanager_proxy`), le A `tofu/dns/mediamanager.tf` et son test,
`mediamanager.sylvain.cloud` de `blocky_rebinding_allowed_domains`, la
ressource, le rôle et la liaison `mediamanager` de
`tofu/pangolin_config/private_resources.tf` (et `pangolin_role.mediamanager`
dans `access_inventory.tf`, son test dans `tests/invariants.tftest.hcl`),
les clés SOPS `mediamanager_wireguard_*` et leurs entrées de rotation,
`docs/apps.md`, `docs/conventions/ansible.md`, `AGENTS.md` ; puis
`grep -rn mediamanager` sur tout le dépôt.
