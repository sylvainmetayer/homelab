# Architecture du homelab

La carte à garder en tête quand quelque chose casse. Le détail des conventions
est indexé par [AGENTS.md](../AGENTS.md) (rôles : leur README.md, transverses : [conventions/](https://github.com/sylvainmetayer/homelab/tree/main/docs/conventions)) ; les procédures d'incident dans
[runbooks/](runbooks/README.md) ; le pourquoi des choix structurants dans
[adr/](adr/README.md).

## Le chemin d'une requête

```mermaid
flowchart LR
  user([Navigateur]) -- "HTTPS 443<br/>DNS OVH *.sylvain.cloud / *.sylvain.dev" --> traefik

  subgraph pangolin_vm["VM Pangolin (Hetzner, IP publique)"]
    direction TB
    traefik["Traefik<br/>certificats Let's Encrypt"]
    bouncer["bouncer CrowdSec (plugin Traefik)<br/>IP bannies : 403"]
    crowdsec["CrowdSec<br/>journal d'accès, AppSec (alertes)"]
    badger["Badger (plugin Traefik)<br/>règles pays/chemins, SSO"]
    pangolin_app["Pangolin<br/>config, SQLite, API"]
    gerbil["Gerbil<br/>WireGuard 51820/21820 UDP"]
    traefik --> bouncer --> badger --> pangolin_app
    bouncer -. "décisions (15 s), AppSec" .-> crowdsec
    traefik -. "même espace réseau<br/>(network_mode: service:gerbil)" .-> gerbil
  end

  gerbil == "tunnel WireGuard" ==> newt_docker
  gerbil == tunnel ==> newt_pi
  gerbil == tunnel ==> newt_flip
  gerbil == tunnel ==> newt_lxc

  subgraph home["Maison (réseau local)"]
    subgraph docker_vm["VM docker (Proxmox, id 100)"]
      newt_docker["newt (dc@newt)"] -- "réseau docker newt" --> app1["rss, nextcloud, …<br/>(dc@service)"]
    end
    subgraph pi["Raspberry Pi"]
      newt_pi[newt] --> immich[immich]
    end
    newt_lxc["LXC newt (Proxmox, id 200)<br/>site proxmox-lxc"] --> lan["ressources privées :<br/>docker-apps.internal, pi.internal,<br/>NAS, Proxmox"]
    subgraph nas["NAS Ugreen (192.168.1.137)"]
      newt_nas["newt (dc@newt)<br/>site nas"] -- "réseau docker newt, 443 et 8443" --> traefik_nas["nas-proxy (dc@nas_proxy)<br/>media. et nas.sylvain.cloud, privés"]
      relay_nas["nas-proxy-443 (dc@nas_proxy)<br/>443 de l'hôte, réseau hôte"] -- "TCP + PROXY v2, 8444" --> traefik_nas
      traefik_nas -- "réseau privé media" --> jellyfin[jellyfin]
      traefik_nas -- "IP LAN, 9999" --> ugos[interface d'UGOS]
    end
  end

  subgraph hetzner_priv["Hetzner, réseau privé 10.0.0.0/16"]
    subgraph flip["flip (10.0.1.10, sans IP publique)"]
      newt_flip[newt] --> fp["flip_planning, demo_planning,<br/>demo_planning_kc, exemple_planning,<br/>promptoramix"]
    end
  end
```

1. Le DNS (`tofu/dns`, chez OVH) envoie tous les sous-domaines vers l'IP
   publique de Pangolin.
2. **Traefik** termine le TLS (certificats Let's Encrypt dans
   `/opt/pangolin/config/letsencrypt`). Le **bouncer CrowdSec** répond 403 aux
   IP bannies (scénarios sur le journal d'accès, liste communautaire ;
   jamais la maison : [runbooks/crowdsec.md](runbooks/crowdsec.md)), puis
   Traefik passe la requête à **Badger**, le
   middleware de Pangolin, qui applique les règles de la ressource : chemins
   publics (priorités 1 à 9), pays FR et DE autorisés (10, 11), pays de voyage
   (20), tout le reste refusé (99). Ensuite seulement vient le SSO. Ce qui
   passe sans lui (applis mobiles, flux, liens de partage, MCP), appli par
   appli : [acces-mobile.md](acces-mobile.md).
3. **Gerbil** porte les tunnels WireGuard. Chaque hôte fait tourner un
   **Newt** qui ouvre un tunnel *sortant* vers Pangolin : aucun port entrant
   n'est ouvert à la maison ni sur flip.
4. Newt joint le conteneur par son nom sur le réseau Docker `newt`. Un
   conteneur qui n'est pas sur ce réseau est injoignable, même s'il tourne.
5. Si toutes les cibles d'une ressource sont en échec de healthcheck, Pangolin
   sert sa **page de maintenance** (réponse 200). Le moniteur Uptime Kuma
   cherche le titre de cette page (mot-clé inversé) : le trouver = DOWN
   (`tofu/pangolin_config/maintenance.tf`).

Tout ce routage (ressources, cibles, règles, rôles SSO, moniteurs Uptime
Kuma) est déclaré dans `tofu/pangolin_config/`, une entrée de
`local.websites` par appli (`website_<app>.tf`). Aucun label Docker.

Une exception, Jellyfin sur le NAS, qui n'est pas public : une seule adresse,
`https://media.sylvain.cloud`, sans rien exposer sur Internet. Le A public
`media.sylvain.cloud` (`tofu/dns/media.tf`) vise l'IP **LAN** du NAS et prime
sur le joker `*.sylvain.cloud`. Un Traefik propre au NAS (`nas-proxy`, rôle
`nas_proxy`, unité `dc@nas_proxy`) termine le TLS avec un certificat Let's
Encrypt obtenu par DNS-01 OVH, puis passe à Jellyfin. Il sert de même
l'interface d'UGOS : `https://nas.sylvain.cloud` (A public vers l'IP LAN
du NAS, `tofu/dns/nas.tf`), à la maison comme avec le client Pangolin
(ressource privée `nas.sylvain.cloud` du site `proxmox-lxc`, qui vise l'IP LAN
du NAS en TCP 22, 443, 445, 8443 et 9999). Secours : `http://192.168.1.137:9999`.
L'Uptime Kuma de PikaPods ne joint pas ces deux noms : le NAS vérifie
lui-même chaque matin l'échéance de leurs certificats
(`nas-proxy-cert-check.timer`) et pousse le résultat au moniteur
« Certificats NAS », rouge sous 14 jours restants ou sans nouvelles depuis
deux jours.

- En LAN : `https://media.sylvain.cloud`, sans port, ou en `:8443`. Repli :
  `http://192.168.1.137:8096`.
- Dehors, avec le client Pangolin (rôle `jellyfin`) : les mêmes adresses. La
  ressource privée du même nom (alias) vise Traefik sur le réseau `newt`, en
  TCP 443 et 8443 : une appli réglée à la maison n'a pas à changer d'adresse.

Deux ports, parce que le 443 du NAS n'est à nous que tant que l'interface
d'UGOS ne le reprend pas. Le 8443 est publié par Docker sur `nas-proxy` et ne
dépend de rien d'autre. Le 443 de l'hôte n'est libre que si la redirection
HTTPS de l'interface d'UGOS est décochée (sinon son nginx y répond par un 307
vers `:9443`) ; il est tenu par un relais, `nas-proxy-443`, second service du
même compose : un Traefik en réseau hôte qui passe chaque connexion TCP telle
quelle à `nas-proxy` (entrée non publiée `8444`, en PROXY protocol v2 pour
garder l'IP du client). Si une mise à jour d'UGOS recoche la redirection,
nginx prend le 443 au boot, le relais sort et Docker le relance chaque minute,
mais `nas-proxy` et le 8443 tournent : un 443 publié par Docker sur
`nas-proxy` aurait au contraire empêché tout le conteneur de démarrer. Le
déploiement (`--tags nas_proxy`) échoue alors en le disant. Rien ne garantit
pourtant que nginx démarre avant Docker : si le relais tient déjà le 443
quand nginx (re)démarre avec la case recochée, c'est nginx qui échoue, et
toute l'interface d'UGOS avec lui ; secours en SSH : `docker stop
nas-proxy-443`, redémarrer nginx, décocher la case, `docker start
nas-proxy-443`. Le port 80 reste au nginx d'UGOS (le DNS-01 n'en a pas
besoin).

Le mode d'emploi (applis, cast, dépôt et nommage des fichiers, causes de
transcodage, commande ffmpeg de la version 1080p) est dans [media.md](media.md).

## Où tourne quoi

| Hôte | Où | Créé par | Configuré par | Ce qui tourne |
|---|---|---|---|---|
| `pangolin` | Hetzner Cloud (nbg1), IP publique | `tofu/pangolin` | `ansible/pangolin.yaml` | pile Pangolin (`pangolin.service`, unité **système**, root), NAT du réseau privé (`nat-gateway.service`), ufw + fail2ban, CrowdSec (HTTPS) |
| `flip` | Hetzner Cloud (fsn1), **sans IP publique** | `tofu/pangolin/flip.tf` | `ansible/flip.yml` | Flip Planning (prod, démo, démo Keycloak), Promptoramix |
| `docker` | VM Proxmox 100 (3 cœurs, 12 Gio, sur le SSD M.2 SATA de l'hôte) | `tofu/proxmox` | `ansible/docker.yml` | toutes les autres applis |
| `pi` | Raspberry Pi, réseau local | à la main | `ansible/pi.yml` | Immich, Blocky (DNS, conteneur) ; gardé hors de Proxmox pour isoler Immich ([ADR 0020](adr/0020-garder-le-raspberry-pi-pour-immich.md)) |
| LXC newt | conteneur Proxmox 200 | `tofu/proxmox` | `ansible/lxc.yml`, à la main seulement (rôles `security`, `newt_service`, `beszel_agent`, `log_agent` et `blocky`, identifiants lus dans l'état `pangolin_config`) | le Newt du site `proxmox-lxc` : ressources privées du réseau local ; Blocky (DNS, binaire) |
| NAS | Ugreen (UGOS Pro), réseau local, 192.168.1.137 | à la main | `ansible/nas.yml`, à la main seulement | exports NFS, Jellyfin, Traefik du NAS (`nas_proxy`), Newt du site `nas`, copie de kDrive, borgmatic en conteneur ; stockage des sauvegardes vzdump |
| `pve` | hôte Proxmox VE, réseau local | à la main | `ansible/pve.yml`, à la main seulement | la VM docker et le LXC newt ; agent Beszel, test de restauration vzdump, avis de mises à jour |
| Storage Box | Hetzner | `tofu/pangolin` | `ansible/backup.yaml` | dépôts Borg |

Sur les hôtes à applis (`docker`, `pi`, `flip`), chaque appli est un projet
Compose dans `/opt/apps/<service>`, lancé par l'unité systemd **utilisateur**
`dc@<service>` de `sylvain` (modèle `ansible/roles/docker_service`). Newt
lui-même est `dc@newt`. Sur le NAS, le même modèle tourne en unité
**système**, root, sous `/volume1/docker/<service>`.

**flip** n'a pas d'IP publique (choix assumé, Pangolin en point unique :
[ADR 0019](adr/0019-flip-sans-ipv4-publique.md)) :

- il sort sur Internet par Pangolin : route `0.0.0.0/0` du réseau privé vers
  Pangolin (`hcloud_network_route.nat`, `tofu/pangolin/nat.tf`), MASQUERADE
  posé par `nat-gateway.service` (rôle `nat_gateway`), route par défaut et DNS
  maintenus côté flip par `nat-client-watchdog` (rôle `nat_client`) ;
- on s'y connecte en SSH par rebond sur Pangolin (`mise run ssh_flip` dans
  `ansible/`, ProxyCommand généré par `ansible/inventory/hetzner.py`) ;
- `flip.internal` (ressource privée Pangolin) passe par le Newt de flip
  lui-même : jamais pour Ansible, une play qui relance newt couperait sa
  propre connexion.

## Le DNS de la maison (Blocky)

Le DHCP de la Bbox annonce deux résolveurs Blocky (rôle `blocky`,
[ADR 0012](adr/0012-filtrage-dns-blocky.md)) : le LXC newt (192.168.1.200,
binaire, `lxc.yml`) et le Pi (192.168.1.96, conteneur publié sur son IP LAN
seule, `pi.yml`). Une panne de l'un passe inaperçue des clients, qui
basculent sur l'autre.

- **Amont** : DNS-over-TLS vers Quad9 et Mullvad (`parallel_best`), amorcé par
  leurs IP (`bootstrapDns`) : Blocky ne dépend ni du `resolv.conf` de son hôte
  ni de la Bbox. Cache et préchargement des noms fréquents.
- **Filtrage** : HaGeZi Pro (publicités, traqueurs) et HaGeZi TIF medium
  (domaines malveillants), téléchargées chaque jour, copie gardée sur disque ;
  réponse `0.0.0.0`. Exceptions : `blocky_allowlist`, par PR. Groupes par
  client possibles (`blocky_client_groups`), un seul aujourd'hui.
- **Noms locaux** : le domaine `lan` (noms du DHCP de la Bbox, `pi.lan`,
  `data.lan`…) et la zone inverse du LAN renvoyés à la Bbox ; `pve.lan`,
  `docker.lan`, `nas.lan`, `newt-lxc.lan` déclarés dans le rôle.
- **Rebinding** : une réponse publique qui pointe dans le LAN est vidée, sauf
  `media.sylvain.cloud` et `nas.sylvain.cloud` (A de `tofu/dns` vers le NAS).
- **Aucun journal des requêtes.**
- **Supervision** : Uptime Kuma (PikaPods) ne joint pas le LAN ; chaque hôte
  vérifie son Blocky toutes les 5 minutes (`blocky-check.timer` : un nom qui
  résout, un nom bloqué) et pousse aux moniteurs « DNS Raspberry Pi » et
  « DNS LXC newt » (`tofu/pangolin_config/cron_dns.tf`), alertes sur
  Telegram et ntfy.
  La même unité écrit aussi les requêtes et blocages depuis son passage
  précédent (`blocky_stats.py`, lu sur le port HTTP local de Blocky, qui ne
  quitte jamais 127.0.0.1) : VictoriaLogs les reçoit par l'agent de
  journaux, la carte « Blocky » de Homepage en fait la somme sur 24 h.
- **Dehors** : le client Pangolin d'un téléphone peut envoyer son DNS dans le
  tunnel vers 192.168.1.200 (ressource privée `dns`), réglage à faire dans
  l'appli ([runbook](runbooks/dns-blocky.md)).

## D'où vient chaque secret

```mermaid
flowchart LR
  agekey["Clé age perso<br/>~/.age.key (.sopsrc)"]
  root["secrets/secrets.sops.yaml<br/>jetons Hetzner, OVH, Cloudflare,<br/>Proxmox, S3, Uptime Kuma,<br/>passphrase des states"]
  ans["secrets/ansible.sops.yaml<br/>mots de passe des applis,<br/>passphrase Borg, sous-comptes,<br/>clés S3 de lecture du state"]
  agekey --> root
  agekey --> ans
  root -- "mise (_.file) + data sops_file" --> tofu[OpenTofu]
  ans -- "community.sops.load_vars" --> ansible[Playbooks]
  ans -- "data sops_file (tofu/github)" --> gh["Secrets GitHub<br/>environnement production"]
  gh -- "SOPS_AGE_KEY, SSH_PRIVATE_KEY,<br/>OLM_ID/SECRET" --> ci[CI de déploiement]
  ci --> ansible
  tofu -- "states sur S3 OVH" --> s3[("homelab-tf-state-sylvain")]
  s3 -- "state pangolin_config (en clair) :<br/>URL push, identifiants Newt de flip" --> ansible
```

- **Où** : les deux fichiers SOPS et l'inventaire de rotation vivent dans le
  dépôt privé `homelab-secrets`, monté en sous-module à `secrets/`
  ([ADR 0018](adr/0018-secrets-depot-prive.md)) ; la CI le clone avec une
  clé de déploiement en lecture seule (`HOMELAB_SECRETS_SSH_KEY`).
- **Destinataires age** (`.sops.yaml`, post-quantiques `age1pq1…`) : `perso`
  `pro` et `secours` pour les deux fichiers ; `github-actions` pour `secrets/ansible.sops.yaml` seulement
  (la CI n'a pas les jetons cloud).
- **States OpenTofu** : tous dans le bucket S3 `homelab-tf-state-sylvain`
  (OVH, `s3.eu-west-par.io.cloud.ovh.net`). Ceux de `pangolin`, `github`,
  `s3_state` et `keepass_backup` sont **chiffrés** (`encryption.tf`, AES-GCM, passphrase
  `TF_VAR_state_encryption_passphrase` de `secrets/secrets.sops.yaml`, sans repli en clair).
  Celui de `pangolin_config` reste en clair parce qu'Ansible le lit : un
  utilisateur S3 dédié (`tofu/s3_state/user_ansible.tf`) n'a le droit que de
  lire cet objet.
- **Ordre d'application** : `tofu/pangolin` d'abord (`pangolin_config` et
  `dns` lisent son state), puis `tofu/pangolin_config`, puis les playbooks.

## Ce que déploie la CI, et quand

| Workflow | Quand | Ce qu'il fait |
|---|---|---|
| `lint.yaml` | chaque PR | jobs `Ansible lint` (+ `check_sops_shadowing.py`), `OpenTofu lint`, `CI lint` (zizmor, actionlint, hadolint) |
| `test.yaml` | chaque PR (sélection), le lundi et à la main (tout) | un job par scénario Molecule et par module Tofu atteint par la PR (`select_tests.py` ; label `full-tests` : tout), récapitulés dans `Tests` |
| `codeql.yaml` | le lundi, à la main, PR et push sur `main` touchant `.github/scripts/**` | analyse CodeQL (`actions`, `python`) vers l'onglet Security ; la configuration par défaut de GitHub reste désactivée |
| `deploy-docker-app.yaml` | **push sur `main`** touchant `ansible/roles/**` ou un playbook d'hôte ; ou à la main | déduit les tags des rôles modifiés (`resolve_docker_tags.py`), monte le tunnel OLM, lance le(s) playbook(s) sur les vrais hôtes |

- **Merger = déployer.** Le ruleset `main` (`tofu/github/ruleset_homelab.tf`)
  exige une PR et les checks `Ansible lint`, `OpenTofu lint`, `Tests` et
  `CI lint` ; le rôle admin peut contourner (correctif urgent).
- Les secrets du déploiement sont dans l'environnement GitHub `production`,
  lisible depuis `main` seulement (`tofu/github/environments.tf`).
- La CI ne lance **jamais** `tofu apply` : l'infra et le routage Pangolin
  s'appliquent à la main.
- Renovate : épingle les images par digest, ne propose une version tierce
  que 3 jours après sa publication (`minimumReleaseAge`), ne rebase une PR
  que si elle est en conflit ; toute montée majeure (hors nos images)
  attend une case cochée sur le Dependency Dashboard, l'issue #5 (la MariaDB officielle
  de Nextcloud n'en voit aucune : elle reste sur la LTS 12.3, et son Redis
  `-bookworm` sur la 8.2). Les digests et les correctifs (hors
  `planning-equipes` et `promptoramix`) arrivent groupés le lundi avant 9 h,
  en deux PR :
  - « weekly stateless automerged updates » **fusionne seule** (auto-merge
    GitHub, une fois les quatre checks du ruleset verts, donc déployée dans la
    foulée) : les images sans base ni migration de données, sur liste
    blanche (`gotenberg`, `tika`, `stirling-pdf`, `homepage`, `nginx`,
    `karakeep-chrome`, `rclone`, et `debian`, la base de l'image Molecule),
    hors du rôle `flip_planning` (le redémarrage emporterait le planning de
    production et sa base), et les correctifs des GitHub Actions
    (`uses:` ; jamais un digest seul, signe d'un tag déplacé) ;
  - « weekly digest and patch updates », tout le reste, à fusionner à la main.

  Les mineures arrivent dans la même fenêtre, une PR par paquet (pas de
  groupe : la migration de données de chaque appli se lit et se déploie à
  part), à la main (les groupes nommés, `beszel`,
  `pangolin-role-dependencies`…, gardent leur PR, le lundi aussi).
  Fusionnent seules aussi, sans délai ni fenêtre du lundi : les versions de
  `planning-equipes` (mineures et correctifs) et de `promptoramix`. Le chemin
  rapide d'un correctif de sécurité d'image n'est pas Renovate : l'alerte
  CRITICAL du lundi de `trivy.yaml`, puis un bump à la main. Rien de ce qui touche `path_bypass_images.json`
  ne fusionne seul : la note de la PR demande de relire les sources listées
  dans `reread` avant le merge à la main.

## Les sauvegardes

```mermaid
flowchart LR
  subgraph host["Chaque hôte (docker, pi, pangolin, flip, nas)"]
    timer["borgmatic.timer<br/>01:00"] --> bm["borgmatic (root)<br/>/etc/borgmatic.d/app.yaml"]
    bm -- "dump dans le conteneur" --> db[("Postgres / MariaDB")]
    bm -- "sqlite3 VACUUM INTO / .backup" --> sq["/var/lib/borgmatic-sqlite/app"]
  end
  bm -- "borg sur SSH, port 23<br/>clé /root/.ssh/borgmatic_storage_box_ed25519" --> sub["Sous-compte backup-hôte<br/>voit seulement backup/hôte/"]
  sub --> box[("Storage Box<br/>9 snapshots quotidiens")]
  bm -- "push après succès" --> kuma[Uptime Kuma]
```

- **Un dépôt Borg par appli**, chiffré (`repokey-blake2`, passphrase
  `backup_passphrase`), dans le dossier de son hôte : `backup/<hôte>/<app>`.
- **Un sous-compte Storage Box par hôte** (`tofu/pangolin/storage_box_subaccounts.tf`) :
  root compromis sur un hôte ne voit pas les dépôts des autres. La clé de root
  est générée sur l'hôte (rôle `borgmatic`) et autorisée chez son sous-compte
  par `ansible/backup.yaml`.
- **Snapshots** de la Storage Box (`tofu/pangolin/storage_box.tf`) : 9
  automatiques, qu'aucun sous-compte ne peut effacer. C'est le filet si un
  hôte compromis efface ses dépôts. Ils disparaîtraient avec la box : elle
  porte `delete_protection` (l'API refuse sa suppression tant que la
  protection n'est pas levée) en plus du `prevent_destroy` de tofu.
- **Pangolin** a en plus les sauvegardes Hetzner de sa VM (`backups = true`,
  7 images quotidiennes) : la reprise rapide, même IP et même clé d'hôte
  ([runbooks/reconstruction-pangolin.md](runbooks/reconstruction-pangolin.md)).
  Elles restent chez Hetzner et partent avec le serveur : Borg reste la copie
  de référence.
- Rétention Borg : 7 quotidiennes, 4 hebdomadaires, 6 mensuelles, 1 annuelle.
- Un modèle unique, `ansible/roles/borgmatic/templates/app.yaml.j2`, appelé
  par chaque rôle via `include_role: borgmatic tasks_from=app.yml`.
- **Le NAS** (Jellyfin : configuration et base SQLite, jamais les médias,
  qui n'ont que les instantanés d'UGOS) : rien ne s'installe sous UGOS,
  borgmatic y tourne dans son image officielle (`borgmatic_install:
  container`, `host_vars/nas`). `borgmatic.timer` (02:30) lance
  `docker compose run --rm` par l'enrobage `/volume1/docker/borgmatic/borgmatic`,
  configurations et clé sous `/volume1/docker/borgmatic`, montées au même
  chemin dans le conteneur ; même modèle, même dépôt par appli, sous-compte
  `backup-nas`.
- **L'hôte Proxmox** sauvegarde en plus la VM docker et le LXC newt entiers
  (job vzdump de `tofu/proxmox/backup.tf`, 21:00, sur le NFS du NAS). Le 2 et
  le 16 du mois, `vzdump-restore-test.timer` (rôle `vzdump_restore_test`,
  `pve.yml`) restaure le LXC sur un id jetable, sans réseau, le démarre puis
  le détruit, et vérifie l'archive entière de la VM ; résultat sur ntfy et au
  moniteur « Test restauration vzdump » :
  [runbooks/test-restauration-vm.md](runbooks/test-restauration-vm.md).
- Restauration : [runbooks/sauvegarde-et-restauration.md](runbooks/sauvegarde-et-restauration.md)
  et [backup-restore.md](backup-restore.md).

## La supervision (Beszel)

Uptime Kuma dit si une appli répond et si ses sauvegardes passent ; Beszel
dit comment vont les hôtes : CPU, mémoire, disques, réseau, conteneurs, et
S.M.A.R.T. là où il y a des disques physiques. Un hub (rôle `beszel`, VM
docker, `monitoring.sylvain.cloud` derrière le SSO puis le compte Beszel) et
un agent par hôte (rôle `beszel_agent`). Les agents ouvrent eux-mêmes une
WebSocket vers le hub : aucun n'écoute de port.

Chaque moniteur Uptime Kuma de `tofu/pangolin_config` alerte sur Telegram et
ntfy (`local.alert_notification_ids`, `notifications.tf`) : Telegram ne passe
pas par Pangolin, ntfy si. Les moniteurs de connexion SSH n'alertent que sur
Telegram. Plus de mail depuis le 2026-10-29. ntfy qui ne joint plus les
téléphones (abonnement refusé, le 2026-10-29) ne se voit pas à son
healthcheck : toutes les 10 minutes, la VM docker relit les relevés « Server
stats » de ntfy (`ntfy-subscribers-check.timer`, rôle `ntfy`) et pousse au
moniteur « ntfy : abonnés » (`cron_ntfy_subscribers.tf`), down quand aucun
abonné n'y figure sur 8 heures (un téléphone hors ligne une nuit
n'alerte pas).

Cadence des sondes (`local.http_probe`, `uptime_globals.tf`, depuis le
2026-10-29) : chaque moniteur HTTP (healthchecks des applis, dashboard
Pangolin, sites externes) sonde toutes les 5 minutes, une seule requête par
appli (BookStack, FreshRSS et Nextcloud sont sondés sur la page où leur
racine redirige, `/login`, `/i/` et `/login`). Un échec met le moniteur en
PENDING et réessaie une minute plus tard ; seul le second échec d'affilée
passe DOWN et alerte : une coupure réelle alerte en 6 minutes au pire (un
peu plus quand l'appli ne répond plus du tout et que chaque essai attend son
`timeout`, 30 à 48 s), un raté isolé jamais. Le retour à UP se voit à la
sonde suivante, jusqu'à 5 minutes plus tard. À une sonde par minute, les healthchecks faisaient les deux tiers du
journal des requêtes de Pangolin (990k lignes sur 1,52M) et pesaient sur sa
base SQLite. Les moniteurs push gardent leur propre intervalle. Côté
Pangolin, Newt sonde chaque cible toutes les 60 s (10 s quand elle est en
échec), pour la page de maintenance et le `check "target_health"` du plan ;
la cible d'une appli en pause n'est plus sondée du tout.

Homepage (`home.sylvain.cloud`) en montre le résumé, groupe Administration :
sur le lien Beszel, le nombre de systèmes et combien sont en ligne ; une carte
Uptime Kuma, la page de statut publique `sylvain-dev`. Homepage les interroge
côté serveur. Les sauvegardes n'ont pas de page de statut publique (leurs
noms et leur état restent dans Uptime Kuma).

Le groupe Supervision, sous Administration, ajoute quatre cartes en lecture
seule, chacune à sa clé sops facultative (`docs/runbooks/rotation-des-secrets.md`,
« Widgets de Homepage ») : les sondes en panne, l'état de chaque sauvegarde et
celui des contrôles périodiques (carte Maintenance : vérificateurs apt du
lundi, quota de la Storage Box, tests de restauration, rotation des secrets
et test de la clé `secours`), lus dans `/metrics` d'Uptime Kuma avec une clé d'API qui n'ouvre que cette
route, par le petit conteneur `kuma-summary` (aucune page de statut, la clé
reste dans `compose.yaml`) ; CrowdSec (alertes des 24 dernières heures, IP
bannies depuis 4 h) compté dans VictoriaLogs, où le Vector de Pangolin envoie
déjà ses lignes, par un compte vmauth qui ne voit que le flux de CrowdSec : la
LAPI reste fermée sur Pangolin. Les cartes d'hôte passent le disque en rouge
à 80 % ; celui du NAS est `/volume1`. Détail : `ansible/roles/homepage/README.md`.

Le widget Beszel exige un superuser PocketBase : il a le sien
(`beszel_homepage_email`, `host_vars/docker` ; clé sops
`homepage_beszel_password`), que le rôle `beszel` crée par
`beszel superuser upsert`, distinct du compte administrateur. **Risque
accepté** (Sylvain, 2026-10-28) : un superuser lit et écrit tout le hub, donc
qui lit la configuration de Homepage (`0600`, VM docker) a la main sur Beszel.
Homepage 2.7.0 ne sait pas faire autrement : sa version 2 du widget se
connecte en dur par `collections/_superusers` (`src/widgets/beszel/widget.js`).

**Rétabli le 29/10/2026**, après une coupure le même jour. Le hub a des
« superuser IPs » (réglage PocketBase `superuserIPs`, posé dans l'interface :
une IP publique, plus `172.16.97.3` depuis le 29/10) : PocketBase vérifie le
mot de passe, puis répond 403 « You are not allowed to perform this
request. » à tout superuser venu d'une autre adresse
(`apis/record_helpers.go` de PocketBase 0.40.5, celui de Beszel 0.21.1 ; un
mauvais mot de passe donne 400). Homepage, sur newt, n'y est pas. D'où le réseau du widget, `beszel_homepage` (interne, `172.16.97.0/29`,
`host_vars/docker`) : créé par `dc@beszel` (hub en `172.16.97.2`), rejoint par
Homepage en `172.16.97.3`, son adresse source vers le hub. Le rôle `beszel`
ne bloque plus la play : un 403 prouve que le mot de passe est bon (depuis
l'hôte, la source est la passerelle Docker), et tout autre échec avertit et
fait omettre le widget pour le run.

Pour le rétablir après une coupure :

1. Dans l'interface PocketBase du hub (`https://monitoring.sylvain.cloud/_/`,
   depuis la maison : seule l'IP déjà listée y ouvre une session superuser),
   Settings → Application, volet « Superuser IPs » : ajouter `172.16.97.3`
   après l'IP existante (liste séparée par des virgules), sans la retirer.
2. `beszel_homepage_email: homepage@monitoring.sylvain.cloud` dans
   `host_vars/docker`, puis `ansible-playbook docker.yml --tags beszel,homepage`
   (les deux : `dc@beszel` crée le réseau que Homepage rejoint).
3. Le lien Beszel de Homepage montre les compteurs ; sinon, « API Error » du
   widget = adresse toujours refusée.

Pour le couper : `beszel_homepage_email` vide, le même `--tags`, puis
`docker network rm beszel_homepage` sur la VM (`docker compose up` ne
supprime pas un réseau retiré du compose) et `172.16.97.3` retiré des
« Superuser IPs ». Le compte du widget reste sur le hub : le retirer à la main
(interface PocketBase `/_/`) si la coupure dure.

**Risque accepté** (Sylvain, 2026-10-29) : la liste d'IP ne protège que ce
qui passe par Traefik. Le réglage `trustedProxy` du hub (`X-Forwarded-For`,
IP la plus à droite, posé dans l'interface) vaut pour toute requête, d'où
qu'elle vienne : PocketBase ne vérifie pas qu'elle passe par un proxy. Par
`monitoring.sylvain.cloud`, Traefik ajoute la vraie IP en dernier : la liste
joue son rôle. Mais tout ce qui joint le hub en direct peut annoncer
`172.16.97.3` dans cet en-tête : le LAN sur le port publié
(`192.168.1.216:8090`, celui des agents du LAN), la VM elle-même
(`127.0.0.1:8090`) et tout conteneur du réseau `newt`, où le hub est
joignable. Seul le mot de passe, exigé partout, les arrête.

**Les autres widgets de Homepage.** Depuis le 29/10/2026, Homepage montre
aussi, sans aucune clé : la recherche
(DuckDuckGo), la date et l'heure, la météo de Talence (Open-Meteo, côté
serveur) ; une pastille d'état et de latence (`siteMonitor`, HEAD puis GET,
« up » jusqu'à 403) sur chaque lien dont l'adresse interne est connue. Pour
les applications de la VM docker, c'est la cible de Pangolin et le chemin de
sa sonde (champs `internal_url` et `site_monitor` de l'output
`homepage_links`), joints par le nom du conteneur sur newt ; l'Immich du Pi,
Jellyfin et Proxmox par leur IP du LAN (rôle `homepage`). Pas de pastille pour
flip (réseau privé de Hetzner, hors de portée de la VM docker), ni pour
immich-swipe et immich-selfie-timelapse (ports non publiés sur le Pi), ni
pour Pangolin et la page de statut.

Avec le superuser du widget Beszel : une carte par hôte (groupe Hôtes, une
par clé de `beszel_agent_tokens`, mode `systemId`), avec le CPU et la mémoire
de l'invité Proxmox pour la VM docker (100) et le LXC newt (200) quand le
jeton Proxmox existe.

Avec une clé sops chacun (vide : widget absent, la page se déploie sans) :
Proxmox, Pangolin, Speedtest Tracker et Immich, en lecture seule ; l'agenda
(liens publics iCal des agendas Nextcloud Perso et Top nous, une clé
chacun, servis par le chemin `/remote.php/*`
déjà ouvert sans SSO aux clients, `website_nextcloud.tf` ; Homepage ne les
lit pas lui-même : le conteneur `ical-filter` de son projet les récupère, en
retire les tâches et journaux, VTODO et VJOURNAL, que le widget afficherait
comme des événements datés de l'instant présent, et les lui sert sur le
réseau privé du projet, cache de 5 minutes ; détail dans le
[README du rôle](../ansible/roles/homepage/README.md)) ; et Jellyfin,
Homebox, Karakeep, FreshRSS, Grocy, Papra et Dawarich. Les trois derniers,
comme les prochains passages du bus 31 à l'arrêt CREPS (flux temps réel
ouvert de Bordeaux Métropole, sans compte), passent par le conteneur
`apps-summary` du projet, sur newt, qui ramène leurs réponses à quelques
nombres. Création de chaque jeton, droits minimaux et `sops set` :
[runbooks/rotation-des-secrets.md](runbooks/rotation-des-secrets.md#widgets-de-homepage).

**Risque accepté** (Sylvain, 2026-10-29) : Jellyfin (clé d'API
d'administration), Homebox (compte invité dans le groupe, qui peut écrire)
et Karakeep (clé d'API de l'utilisateur) n'ont pas de jeton en lecture
seule ; qui lit la configuration de Homepage (`0600`, VM docker) peut donc
administrer Jellyfin et écrire dans Homebox et Karakeep. Même chose, à
accepter avec les cartes de la deuxième série, pour FreshRSS (le mot de
passe d'API marque lu et abonne ; l'API, coupée sinon, n'est ouverte qu'avec
la clé, et seulement sur newt : Pangolin n'ouvre aucun chemin autour du
SSO), Grocy (utilisateur dédié sans permission, mais l'API lit tout) et
Dawarich (une seule clé par compte, qui écrit aussi des points). Le widget Jellyfin
est rendu sans ses boutons pause/lecture (`enableMediaControl: false`).

```mermaid
flowchart LR
  subgraph lan["LAN"]
    subgraph vm["VM docker"]
      hub["hub Beszel<br/>publié sur 127.0.0.1 et 192.168.1.216:8090"]
      ad["agent docker"] -- "127.0.0.1:8090" --> hub
    end
    api["agent pi"] -- "192.168.1.216:8090" --> hub
    anas["agent NAS"] -- "192.168.1.216:8090" --> hub
    alxc["agent newt-lxc (binaire)"] -- "192.168.1.216:8090" --> hub
    apve["agent pve (binaire, S.M.A.R.T.)"] -- "192.168.1.216:8090" --> hub
  end
  subgraph hetzner["Hetzner"]
    ap["agent pangolin"]
    af["agent flip (via le NAT de Pangolin)"]
  end
  ap -- "https://monitoring.sylvain.cloud<br/>PASS /api/beszel/agent-connect<br/>+ jeton d'accès Pangolin" --> pg["Pangolin / newt"] --> hub
  af -- "idem" --> pg
```

- **Hôtes Hetzner** : par la ressource publique, sur le seul chemin
  `/api/beszel/agent-connect`, en PASS (les règles pays sautées : leur IP
  source est privée), avec un jeton d'accès Pangolin par agent
  (`website_beszel.tf`, sortie `beszel_agent_hub_headers`, envoyé en
  `HUB_HEADERS`). Sans jeton, rien n'atteint le hub.
- **Hôtes du LAN** : par le port publié sur la VM docker. Docker publie avant
  ufw, donc **l'interface du hub répond sans SSO à tout le LAN** : le compte
  Beszel (mot de passe `beszel_admin_password`) y est la seule barrière.
- **Authentification d'un agent** : son jeton (`beszel_agent_tokens`, un par
  hôte, déclaré dans le `config.yml` du hub), la clé du hub
  (`beszel_hub_public_key`, le hub signe avec `beszel_hub_private_key`), puis
  son empreinte, que le hub fige à la première connexion. Un hôte reconstruit
  (dossier `data/` de l'agent perdu) est refusé : remettre son empreinte à
  zéro dans le hub (menu du système, jeton et empreinte).
- **`config.yml` fait autorité** : un hôte retiré de `beszel_agent_tokens`
  disparaît du hub avec son historique au redémarrage suivant.
- **Socket Docker** : jamais monté dans l'agent. Un proxy
  (`wollomatic/socket-proxy`, sidecar du compose de l'agent, sans réseau) ne
  laisse passer que les GET dont l'agent a besoin (liste des conteneurs,
  statistiques, version, info, logs d'un conteneur par son identifiant) : ni
  inspect, ni écriture. Newt a le même proxy (rôle `newt`, #853) : liste des
  conteneurs, inspect de lui-même et flux d'événements, rien d'autre. Ce
  socket ne sert qu'à la liste des conteneurs affichée par Pangolin : aucun
  routage n'en dépend.
- **Logs des conteneurs** : la fiche d'un conteneur dans l'interface
  (`CONTAINER_DETAILS=true` côté hub) montre ses 200 dernières lignes,
  demandées à l'agent à chaque ouverture et jamais stockées dans le hub. Tout
  compte Beszel qui voit le système les lit, et sur le LAN ce compte est la
  seule barrière : un token ou un mot de passe qu'une appli écrit dans ses
  logs y devient lisible. L'onglet inspect de la même fiche reste vide : le
  proxy le refuse (403 dans ses logs à chaque ouverture), parce que l'agent
  n'en retire que les variables d'environnement, pas les arguments de
  commande (le `--requirepass` du redis de nextcloud) ni les labels. Sur le
  LXC newt et l'hôte Proxmox (agent binaire, sans Docker), ni fiche de
  conteneur ni logs des services systemd suivis (`SERVICE_PATTERNS`) :
  l'utilisateur éphémère de l'unité (`DynamicUser`) n'est dans aucun groupe
  du journal, l'agent le trouve illisible et coupe ces logs
  (`SupplementaryGroups=systemd-journal` ouvrirait tout le journal).
- **Lancement** : `dc@beszel_agent` (unité user) sur docker, pi et flip ;
  `dc@beszel_agent` en unité système sur le NAS (`nas.yml`, à la main) ;
  `docker compose up -d` et la restart policy sur Pangolin (pas de
  `docker_service`) ; un service systemd sur le LXC newt (`lxc.yml`, à la
  main) et sur l'hôte Proxmox (`pve.yml`, à la main, en root sans become :
  pas de sudo sur l'hôte), qui lit aussi le S.M.A.R.T. de `sda`, le SSD M.2
  SATA qui porte toutes les VM et le LXC (`CAP_SYS_RAWIO`, groupe `disk` et
  `DeviceAllow=/dev/sda r` dans l'unité). L'hôte Proxmox n'a que cet agent et le vérificateur des mises à
  jour (ci-dessous) : ni `00-setup`, ni `security`.
- **Mises à jour** : ni l'hôte Proxmox ni UGOS ne se mettent à jour seuls ;
  la VM docker, le Pi, flip et Pangolin n'installent seuls que
  Debian-Security (`unattended-upgrades`), Docker restant à la main exprès
  (redémarrer `dockerd` redémarre toutes les applis de l'hôte). Le rôle
  `update_notify` (`pve.yml`, `docker.yml`, `pi.yml`, `flip.yml`,
  `pangolin.yaml`) publie chaque lundi sur le topic `scripts` de ntfy ce qui
  attend sur chacun de ces hôtes, et seulement s'il y a quelque chose
  (sécurité d'abord, puis Docker, Proxmox et noyaux ; priorité haute s'il y
  a de la sécurité) ; un moniteur push « Mises à jour <hôte> » par hôte pour
  un vérificateur mort. UGOS ne dit pas sans session de son interface si une
  mise à jour attend : rien ne le surveille, ses mises à jour se regardent
  dans l'interface. Procédure :
  [runbooks/mises-a-jour-hotes.md](runbooks/mises-a-jour-hotes.md).
- **Alertes** : déclarées par le rôle `beszel` (`beszel_alerts`, tag
  `beszel_alerts`) sur tous les systèmes : hôte muet 5 min, CPU et mémoire à
  plus de 90 % sur 10 min, disque à plus de 85 % ; température au-dessus de
  80 °C sur le Pi, le NAS et pve. Le S.M.A.R.T. (WARNING/FAILED) prévient d'office, sans alerte à
  déclarer. `config.yml` ne sait déclarer que les systèmes : alertes et
  canaux vivent dans la base du hub, par utilisateur, et le rôle les pose par
  l'API du hub (`127.0.0.1:8090`, connecté au compte administrateur avec
  `beszel_admin_password`, qui doit donc rester son mot de passe). Elles font
  autorité : une alerte ajoutée dans l'interface est supprimée au déploiement
  suivant. Envoi par e-mail (SMTP Infomaniak réglé dans l'interface du hub),
  et par Telegram dès que les clés sops `beszel_telegram_bot_token` et
  `beszel_telegram_chat_id` existent (URL shoutrrr) : elles ne sont pas
  créées aujourd'hui, Beszel n'alerte donc que par e-mail. Test du canal
  Telegram, une fois les clés posées :
  `ansible-playbook docker.yml --tags beszel_alerts_test` (le bouton « Test »
  des réglages, `POST /api/beszel/test-notification` ; il refuse de tourner
  sans canal Telegram). Si la VM docker tombe,
  Beszel se tait : Uptime Kuma (hors VM) le voit par le moniteur
  `Healthcheck Beszel`.
- **Limites connues** : sur le Pi, le contrôleur cgroup mémoire, coupé par
  le firmware, est réactivé par `cgroup_enable=memory` (#846) ; son S.M.A.R.T.
  passe par un pont USB RTL9210 (`-d sntrealtek`), non vérifié avant
  déploiement ; le LXC newt (non privilégié) ne voit ni S.M.A.R.T. ni
  capteurs fiables, mais son CPU, sa mémoire, son disque et `newt.service`.
- **Rapport mémoire hebdomadaire** (rôle `mem_report`, docker, pi et flip,
  hors Beszel) : chaque lundi à 09:00, `mem-report.timer` lit le cgroup v2 de
  chaque conteneur (`memory.max`, `memory.peak`, `memory.current`,
  `memory.events`) et publie sur ntfy (topic `scripts`, jeton
  `ntfy_scripts_token`) un message par hôte : à agrandir (pic à 80 % de la
  limite ou plus, ou OOM-kill), à réduire (pic sous 25 %, s'il libère
  64 Mio au moins), sans limite, chacun avec une limite suggérée de 2x le
  pic, arrondie (doctrine des limites, [conventions/resource-limits.md](conventions/resource-limits.md)). `memory.peak` et
  `memory.events` repartent de zéro avec le conteneur : un pic mesuré sur
  moins de 7 jours est signalé, et un redémarrage automatique après une
  mise à jour du noyau remet tout l'hôte à zéro. Un OOM-kill du processus
  principal, suivi d'un redémarrage du conteneur, n'apparaît que par
  `redémarré xN` (le nouveau cgroup a perdu le compteur), et un conteneur
  relancé depuis moins de 7 jours n'est jamais proposé à la réduction. À la
  main : `sudo systemctl start mem-report`, le texte complet (lignes coupées
  du message ntfy comprises) dans
  `journalctl -u mem-report`.

## Les journaux (VictoriaLogs)

Beszel montre les 200 dernières lignes d'un conteneur, à la demande ;
VictoriaLogs garde tous les journaux de tous les hôtes **30 jours** et les
interroge en LogsQL. Version légère, à l'essai (#79,
[ADR 0011](adr/0011-journaux-victorialogs.md), « proposée ») : VictoriaLogs
seul, ni Grafana ni métriques. Rôle `victoria_logs` sur la VM docker, interface (vmui)
sur `https://logs.sylvain.cloud/select/vmui/`, derrière le SSO puis le compte
vmauth `sylvain` (mot de passe sops `victoria_logs_ui_password`).

- **Deux conteneurs** : `victoria-logs` (le stockage) n'est que sur un réseau
  interne ; `victoria-logs-auth` (vmauth) est seul à le joindre, sur `newt`
  (cible de Pangolin) et publié sur `127.0.0.1:9428` et
  `192.168.1.216:9428`. VictoriaLogs n'a pas de comptes : sans vmauth, tout
  conteneur de `newt`, et tout le LAN par le port publié (Docker publie avant
  ufw), lirait les journaux. vmauth répond 401 à tout sauf `/health`.
- **Comptes** : `sylvain` voit tout ; un compte par agent
  (`victoria_logs_agent_passwords`, un mot de passe par hôte) ne peut
  qu'écrire, sur le seul chemin `/insert/jsonline` : ni lecture, ni
  suppression. Un hôte compromis peut écrire de faux journaux, pas lire ceux
  des autres.
- **Rétention** : `-retentionPeriod=30d`, et un plafond strict de 5 Gio
  (`-retention.maxDiskSpaceUsageBytes`) au-delà duquel les partitions
  journalières les plus anciennes partent avant les 30 jours (un hôte qui
  boucle sur une erreur). Données sur le disque local de la VM
  (`/opt/apps/victoria_logs/data`), jamais sur le NAS.
- **Agents** (rôle `log_agent`, Vector 0.60, un par hôte) : le journal
  systemd (unités user comprises) et, là où Docker tourne, la sortie de
  chaque conteneur par la source `docker_logs`, à travers son propre proxy du
  socket (GET seulement : liste, événements, inspect et logs d'un conteneur
  par son identifiant ; inspect est nécessaire à Vector, contrairement à
  Beszel, et lui montre l'environnement des conteneurs, qu'il ne garde pas).
  Sous `dc@`, `docker compose up` recopie déjà la sortie des conteneurs dans
  le journal (« conteneur  | ligne ») : ces copies sont écartées, la source
  docker les a avec le nom du conteneur. Sur Pangolin, aussi le journal
  d'accès de Traefik (chaînes de requête retirées : `p_token`, liens de
  partage ; les envois des agents eux-mêmes écartés) et les alertes et
  décisions de CrowdSec, extraites de sa sortie (champs `crowdsec`,
  `client_ip`, `scenario`). Champs de flux : `host`, `source` (`journald`,
  `docker`, `traefik`), `unit`, `container` ; les sessions SSH et les unités
  transitoires y sont repliées (`session.scope`, `run.service`, nom exact dans
  `unit_instance`), sans quoi chaque connexion ouvrirait un flux.

  | Hôte | Mode | Vers vmauth par |
  |---|---|---|
  | docker | `dc@log_agent` | `127.0.0.1:9428` |
  | pi | `dc@log_agent` | le LAN, `192.168.1.216:9428` |
  | NAS | `dc@log_agent` (unité système), journal d'UGOS en lecture seule | le LAN |
  | newt-lxc | binaire Vector, service systemd (`DynamicUser`, groupe `systemd-journal`), journal seulement | le LAN |
  | pangolin | `docker compose up -d` (pas de `docker_service`) | `https://logs.sylvain.cloud` |
  | flip | `dc@log_agent` | `https://logs.sylvain.cloud`, par le NAT de Pangolin |

  Les hôtes Hetzner passent par la ressource publique, sur le seul chemin
  `/insert/jsonline`, en PASS (règles pays sautées : IP source privée), avec
  un jeton d'accès Pangolin par agent (sortie `log_agent_access_tokens`) ;
  vmauth exige encore leur compte. Sur le LAN, le compte de l'agent passe en
  clair, comme le jeton Beszel : il n'ouvre que l'écriture.
- **Secrets des agents** : `secrets.json` (0600 root), lu par le backend
  `file` de Vector ; en binaire, remis à l'unité par `LoadCredential`, comme
  `vector.yaml` (les deux à root en 0600). Jamais
  `${VAR}` : Vector 0.60 n'interpole plus l'environnement sans
  `--dangerously-allow-env-var-interpolation`.
- **Pertes** : le curseur du journal et la position dans le journal d'accès
  n'avancent qu'une fois le lot accepté par VictoriaLogs : une coupure ne perd
  rien tant que l'hôte garde ses lignes. La source docker n'a pas ce suivi :
  ce qu'un conteneur écrit pendant un arrêt de l'agent manque.
- **Pas de sauvegarde** : des journaux se reproduisent (chaque hôte garde son
  journald) et leur perte ne coûte que l'historique. Pas de moniteur
  « Backup », pas d'entrée dans le test de restauration. La configuration est
  dans git, les mots de passe dans sops.
- **Supervision** : Pangolin et le moniteur `Healthcheck VictoriaLogs`
  sondent le `/health` de vmauth (servi sans compte) : ils voient vmauth,
  pas le stockage, dont l'image (distroless) n'a aucun binaire de
  healthcheck.
- **Poids** : stockage plafonné à 320 Mio (`mem_limit`, caches à 60 %), vmauth
  à 64 Mio ; chaque agent conteneur à 256 Mio (relevé après un jour à
  112 Mio de pic sur docker, 97 sur flip), plus 32 Mio pour son proxy du
  socket (`MemoryMax=128M` en binaire) ; pas de `cpus`. Volume attendu : quelques centaines de Mio de
  journaux bruts par jour, tous hôtes compris, qu'il compresse d'un facteur
  10 environ, soit de l'ordre de 1 à 2 Gio pour 30 jours, sous le plafond.
- **Mesure, une semaine après le déploiement** : `memory.peak` du stockage, de
  vmauth et des agents (`/sys/fs/cgroup/system.slice/docker-<id>.scope/memory.peak`),
  puis l'I/O wait de la VM docker dans Beszel, avant et après ; la place
  prise (`du -sh /opt/apps/victoria_logs/data`). Recaler les `mem_limit` à
  ~2× le pic ; trop lourd pour la VM : retour arrière ci-dessous, et l'ADR
  passe en « rejetée ».
- **Retour arrière** : d'abord les agents, `log_agent` retiré des playbooks
  puis, sur chaque hôte, `dc@log_agent` arrêté et `/opt/apps/log_agent` (ou
  `/volume1/docker/log_agent`) supprimé par le même `decommission_app`
  (service `log_agent`), `docker compose down` dans `/opt/apps/log_agent` sur
  Pangolin, `log-agent.service` désactivé et `/usr/local/lib/log-agent`,
  `/etc/log-agent` supprimés sur le LXC ; `website_victoria_logs.tf` perd
  alors sa règle et ses jetons. Puis le serveur : retirer le rôle de
  `docker.yml`, puis
  `ansible-playbook docker.yml --tags decommission -e decommission_app_confirm=true
  -e decommission_app_service=victoria_logs
  -e decommission_app_base_path=/opt/apps/victoria_logs` (rien côté
  borgmatic : aucune sauvegarde), supprimer `website_victoria_logs.tf`, son
  entrée de `local.websites` et le slug `victoria-logs` de `roles.tf` (puis
  `tofu apply`), et les clés sops `victoria_logs_*`. Rien d'autre n'en
  dépend : aucune appli ne lit VictoriaLogs.
