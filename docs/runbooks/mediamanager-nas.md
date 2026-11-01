# MediaManager sur le NAS : appli injoignable, VPN, port redirigé, liens physiques

Essai de MediaManager (rôle `mediamanager`), projet Compose sous
`dc@mediamanager` (**unité système** du NAS), dossier
`/volume1/docker/mediamanager`. Servi par le Traefik du NAS (rôle
`nas_proxy`, `dc@nas_proxy`, conteneur `nas-proxy`) sur
`https://mediamanager.sylvain.cloud` (ou `:8443`). **`nas.yml` ne passe
jamais par la CI** : tout déploiement est à la main. Détail :
[README du rôle](../../ansible/roles/mediamanager/README.md),
[README de nas_proxy](../../ansible/roles/nas_proxy/README.md).

| Conteneur | Rôle |
|---|---|
| `mediamanager` | l'appli, réseaux `default`, `db`, `proxy` |
| `mediamanager-db` | PostgreSQL 17, réseau `db` interne |
| `mediamanager-gluetun` | tunnel WireGuard, kill switch |
| `mediamanager-qbittorrent`, `mediamanager-prowlarr` | dans le réseau de gluetun (`network_mode: service:gluetun`) |

Les trois derniers n'existent qu'avec la clé SOPS
`mediamanager_wireguard_private_key`.

## Symptôme

- `https://mediamanager.sylvain.cloud` ne répond pas, erreur de certificat,
  ou 404 de Traefik.
- Moniteur « Certificats NAS » DOWN (certificat à moins de 14 jours, ou
  contrôle en échec).
- Les téléchargements ne démarrent pas, restent sans pair, ou qBittorrent
  montre l'icône de connexion rouge ou orange.
- Doute sur une fuite : l'IP de la maison vue d'un tracker.
- Un film importé compte deux fois sur le disque.

## Diagnostic

Sur le NAS (`ssh sylvain@192.168.1.137`, LAN ou client Pangolin) :

```bash
sudo systemctl status dc@mediamanager dc@nas_proxy
sudo journalctl -u dc@mediamanager -n 100 --no-pager
cd /volume1/docker/mediamanager && sudo docker compose ps
sudo docker logs --tail 100 mediamanager
```

**Accès (Traefik du NAS).**

- `dc@mediamanager` relancé toutes les 15 s, journal « network
  mediamanager_proxy declared as external, but could not be found » :
  `dc@nas_proxy`, qui crée ce réseau, n'a pas tourné.
- `sudo docker logs --tail 100 nas-proxy` : erreurs ACME (DNS-01 OVH, clés
  `nas_ovh_*`), routeur `mediamanager` absent.
- Le 443 de l'hôte est-il au relais ?
  `sudo docker ps --filter name=nas-proxy-443` ; s'il redémarre en boucle,
  UGOS a repris le 443 (« rediriger HTTP/HTTPS » recoché après une mise à
  jour) : `:8443` marche encore. Voir le README de `nas_proxy`.
- Dehors : le client Pangolin doit être connecté, et Sylvain membre du rôle
  Pangolin `mediamanager` (ressource privée `mediamanager`, site `nas`).
- À la maison : `dig +short mediamanager.sylvain.cloud` doit donner l'IP
  LAN du NAS (Blocky laisse passer ce nom,
  `blocky_rebinding_allowed_domains`).
- Certificat : `sudo systemctl status nas-proxy-cert-check.service` et son
  journal.

**VPN.**

```bash
sudo docker logs mediamanager-gluetun 2>&1 | grep -i -E "public ip|port forward|error" | tail -20
sudo docker exec mediamanager-qbittorrent curl -s --max-time 15 https://ifconfig.io   # IP du VPN
curl -s --max-time 15 https://ifconfig.io                                             # IP de la maison, différente
```

- Le `curl` dans qBittorrent **expire** : tunnel tombé, le kill switch fait
  son travail (rien ne fuit). Lire le journal de gluetun (clé WireGuard
  refusée, serveur injoignable, aucun serveur P2P dans
  `mediamanager_vpn_server_countries`).
- Le `curl` dans qBittorrent rend **l'IP de la maison** : fuite, voir
  Réparation tout de suite.

**Port redirigé** (ProtonVPN, NAT-PMP, différent à chaque connexion) :
`sudo docker logs mediamanager-gluetun 2>&1 | grep -i "port forwarded"`
donne le port ; qBittorrent (tunnel SSH plus bas) doit montrer le même
dans Options → Connexion. Différent ou 0 : la commande
`VPN_PORT_FORWARDING_UP_COMMAND` de gluetun n'a pas atteint qBittorrent
(`WebUI\LocalHostAuth=false` retiré du `qBittorrent.conf`, par exemple).

Interfaces de qBittorrent et Prowlarr, depuis le PC :

```bash
ssh -N -L 8080:127.0.0.1:8080 -L 9696:127.0.0.1:9696 sylvain@192.168.1.137
```

puis `http://localhost:8080` (compte `mediamanager`) et
`http://localhost:9696`.

**Liens physiques.**

```bash
stat -c '%h %i %n' "/volume1/media/.mediamanager-test/films/<Titre (année)>/"*.mkv \
  "/volume1/media/.mediamanager-test/torrents/<nom du torrent>/"*.mkv
```

Attendu : `2` et le même inode sur les deux lignes. `1` : copie au lieu
d'un lien. Causes : `/data` monté deux fois ou différemment dans
`mediamanager` et `mediamanager-qbittorrent`, ou un chemin hors du dossier
partagé `media` (autre sous-volume btrfs).

## Réparation

- **Fuite** : couper tout de suite, `sudo systemctl stop dc@mediamanager`.
  Ne relancer qu'après avoir compris pourquoi qBittorrent n'est plus dans
  le réseau de gluetun (compose modifié à la main ?) :
  `ansible-playbook nas.yml --tags mediamanager --check --diff` depuis
  `ansible/`, puis sans `--check`.
- **Tunnel tombé** : `sudo systemctl restart dc@mediamanager`. Clé refusée :
  en générer une autre chez le fournisseur (ProtonVPN : « NAT-PMP (Port
  Forwarding) » coché), `sops set` de `mediamanager_wireguard_private_key`,
  entrée de rotation à jour, puis `ansible-playbook nas.yml --tags
  mediamanager`.
- **Port non transmis à qBittorrent** : repartir du modèle de
  `qBittorrent.conf` (il n'est posé qu'une fois) :

  ```bash
  sudo systemctl stop dc@mediamanager
  sudo rm /volume1/docker/mediamanager/qbittorrent/qBittorrent/qBittorrent.conf
  # puis, depuis ansible/ sur le PC
  ansible-playbook nas.yml --tags mediamanager
  ```

  Même remède quand MediaManager ne se connecte plus à qBittorrent après
  une rotation de `backup_passphrase` (mot de passe dérivé). La base
  PostgreSQL, elle, demande un `ALTER USER` d'abord
  ([mot-de-passe-base.md](mot-de-passe-base.md)).
- **Route, réseau ou certificat** : `ansible-playbook nas.yml --tags
  nas_proxy,mediamanager` (dans cet ordre dans `nas.yml`). Le 443 repris
  par UGOS : décocher la redirection dans UGOS, puis
  `sudo docker restart nas-proxy-443`.
- **Liens physiques** : ne jamais monter `media/films` ou `media/series`
  dans MediaManager ; le bac à sable `/volume1/media/.mediamanager-test`
  monté une seule fois en `/data` des deux côtés. Relancer le rôle remet le
  compose du dépôt.

## Vérification

- `https://mediamanager.sylvain.cloud` affiche la connexion de MediaManager,
  certificat Let's Encrypt valide.
- Le `curl` dans `mediamanager-qbittorrent` rend une IP différente de celle
  de la maison ; le port de gluetun est celui de qBittorrent, icône de
  connexion verte après quelques minutes.
- Le contrôle des liens physiques donne `2` et le même inode.
- `sudo systemctl start nas-proxy-cert-check.service` puis moniteur
  « Certificats NAS » UP.

## Prévention

- Après toute mise à jour d'UGOS : `nas.yml` (voir
  [mises-a-jour-hotes.md](mises-a-jour-hotes.md)) et le contrôle de fuite
  ci-dessus.
- La base de MediaManager **n'est pas sauvegardée** (borgmatic en conteneur
  sans `docker exec`) : une restauration repart d'une base vide avec la
  configuration restaurée.
