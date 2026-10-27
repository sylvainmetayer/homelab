# Architecture du homelab

La carte à garder en tête quand quelque chose casse. Le détail des conventions
est dans [AGENTS.md](../AGENTS.md) ; les procédures d'incident dans
[runbooks/](runbooks/README.md).

## Le chemin d'une requête

```mermaid
flowchart LR
  user([Navigateur]) -- "HTTPS 443<br/>DNS OVH *.sylvain.cloud / *.sylvain.dev" --> traefik

  subgraph pangolin_vm["VM Pangolin (Hetzner, IP publique)"]
    direction TB
    traefik["Traefik<br/>certificats Let's Encrypt"]
    badger["Badger (plugin Traefik)<br/>règles pays/chemins, SSO"]
    pangolin_app["Pangolin<br/>config, SQLite, API"]
    gerbil["Gerbil<br/>WireGuard 51820/21820 UDP"]
    traefik --> badger --> pangolin_app
    traefik -. "même espace réseau<br/>(network_mode: service:gerbil)" .-> gerbil
  end

  gerbil == "tunnel WireGuard" ==> newt_docker
  gerbil == tunnel ==> newt_pi
  gerbil == tunnel ==> newt_flip
  gerbil == tunnel ==> newt_lxc

  subgraph home["Maison (réseau local)"]
    subgraph docker_vm["VM docker (Proxmox, id 300)"]
      newt_docker["newt (dc@newt)"] -- "réseau docker newt" --> app1["rss, nextcloud, …<br/>(dc@service)"]
    end
    subgraph pi["Raspberry Pi"]
      newt_pi[newt] --> immich[immich]
    end
    newt_lxc["LXC newt (Proxmox, id 200)<br/>site proxmox-lxc"] --> lan["ressources privées :<br/>docker-apps.internal, pi.internal,<br/>NAS, Proxmox"]
    subgraph nas["NAS Ugreen (192.168.1.137)"]
      newt_nas["newt (dc@newt)<br/>site nas"] -- "réseau docker newt, 443 et 8443" --> traefik_nas["jellyfin-traefik<br/>(media.sylvain.cloud, privé)"]
      traefik_nas -- "réseau privé media" --> jellyfin[jellyfin]
    end
  end

  subgraph hetzner_priv["Hetzner, réseau privé 10.0.0.0/16"]
    subgraph flip["flip (10.0.1.10, sans IP publique)"]
      newt_flip[newt] --> fp["flip_planning, demo_planning,<br/>demo_planning_kc, promptoramix"]
    end
  end
```

1. Le DNS (`tofu/dns`, chez OVH) envoie tous les sous-domaines vers l'IP
   publique de Pangolin.
2. **Traefik** termine le TLS (certificats Let's Encrypt dans
   `/opt/pangolin/config/letsencrypt`) puis passe la requête à **Badger**, le
   middleware de Pangolin, qui applique les règles de la ressource : chemins
   publics (priorités 1 à 9), pays FR et DE autorisés (10, 11), pays de voyage
   (20), tout le reste refusé (99). Ensuite seulement vient le SSO.
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
sur le joker `*.sylvain.cloud`. Un Traefik propre au NAS (`jellyfin-traefik`,
dans le compose du rôle `jellyfin`) termine le TLS avec un certificat Let's
Encrypt obtenu par DNS-01 OVH, puis passe à Jellyfin.

- En LAN : `https://media.sylvain.cloud:8443` (80 et 443 du NAS appartiennent
  au nginx d'UGOS). Repli : `http://192.168.1.137:8096`.
- Dehors, avec le client Pangolin (rôle `jellyfin`) : `https://media.sylvain.cloud`,
  sans port. La ressource privée du même nom (alias) vise Traefik sur le
  réseau `newt`, en TCP 443 et 8443 : l'adresse en `:8443` du LAN y marche
  aussi, une appli réglée à la maison n'a pas à changer d'adresse dehors.

## Où tourne quoi

| Hôte | Où | Créé par | Configuré par | Ce qui tourne |
|---|---|---|---|---|
| `pangolin` | Hetzner Cloud (nbg1), IP publique | `tofu/pangolin` | `ansible/pangolin.yaml` | pile Pangolin (`pangolin.service`, unité **système**, root), NAT du réseau privé (`nat-gateway.service`), ufw + fail2ban |
| `flip` | Hetzner Cloud (fsn1), **sans IP publique** | `tofu/pangolin/flip.tf` | `ansible/flip.yml` | Flip Planning (prod, démo, démo Keycloak), Promptoramix |
| `docker` | VM Proxmox 300 (3 cœurs, 12 Gio, disque **rotatif**) | `tofu/proxmox` | `ansible/docker.yml` | toutes les autres applis |
| `pi` | Raspberry Pi, réseau local | à la main | `ansible/pi.yml` | Immich |
| LXC newt | conteneur Proxmox 200 | `tofu/proxmox` | `ansible/lxc.yml` (rôles `security` et `newt_service`, identifiants lus dans l'état `pangolin_config`) | le Newt du site `proxmox-lxc` : ressources privées du réseau local |
| Storage Box | Hetzner | `tofu/pangolin` | `ansible/backup.yaml` | dépôts Borg |

Sur les hôtes à applis (`docker`, `pi`, `flip`), chaque appli est un projet
Compose dans `/opt/apps/<service>`, lancé par l'unité systemd **utilisateur**
`dc@<service>` de `sylvain` (modèle `ansible/roles/docker_service`). Newt
lui-même est `dc@newt`.

**flip** n'a pas d'IP publique :

- il sort sur Internet par Pangolin : route `0.0.0.0/0` du réseau privé vers
  Pangolin (`hcloud_network_route.nat`, `tofu/pangolin/nat.tf`), MASQUERADE
  posé par `nat-gateway.service` (rôle `nat_gateway`), route par défaut et DNS
  maintenus côté flip par `nat-client-watchdog` (rôle `nat_client`) ;
- on s'y connecte en SSH par rebond sur Pangolin (`mise run ssh_flip` dans
  `ansible/`, ProxyCommand généré par `ansible/inventory/hetzner.py`) ;
- `flip.internal` (ressource privée Pangolin) passe par le Newt de flip
  lui-même : jamais pour Ansible, une play qui relance newt couperait sa
  propre connexion.

## D'où vient chaque secret

```mermaid
flowchart LR
  agekey["Clé age perso<br/>~/.age.key (.sopsrc)"]
  root["secrets.sops.yaml (racine)<br/>jetons Hetzner, OVH, Cloudflare,<br/>Proxmox, S3, Uptime Kuma,<br/>passphrase des states"]
  ans["ansible/secrets.sops.yaml<br/>mots de passe des applis,<br/>passphrase Borg, sous-comptes,<br/>clés S3 de lecture du state"]
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

- **Destinataires age** (`.sops.yaml`) : `perso`, `pro` et `secours` pour les
  deux fichiers ; `github-actions` pour `ansible/secrets.sops.yaml` seulement
  (la CI n'a pas les jetons cloud).
- **States OpenTofu** : tous dans le bucket S3 `homelab-tf-state-sylvain`
  (OVH, `s3.eu-west-par.io.cloud.ovh.net`). Ceux de `pangolin`, `github` et
  `s3_state` sont **chiffrés** (`encryption.tf`, AES-GCM, passphrase
  `TF_VAR_state_encryption_passphrase` du SOPS racine, sans repli en clair).
  Celui de `pangolin_config` reste en clair parce qu'Ansible le lit : un
  utilisateur S3 dédié (`tofu/s3_state/user_ansible.tf`) n'a le droit que de
  lire cet objet.
- **Ordre d'application** : `tofu/pangolin` d'abord (`pangolin_config` et
  `dns` lisent son state), puis `tofu/pangolin_config`, puis les playbooks.

## Ce que déploie la CI, et quand

| Workflow | Quand | Ce qu'il fait |
|---|---|---|
| `lint.yaml` | chaque PR | jobs `Ansible lint` (+ `check_sops_shadowing.py`), `OpenTofu lint`, `CI lint` (zizmor, actionlint, hadolint) |
| `test.yaml` | chaque PR | un job par scénario Molecule et par module Tofu testé, récapitulés dans `Tests` |
| `path-bypass-review.yaml` | PR qui touche `path_bypass_images.json` | attend l'approbation de l'environnement `relecture-chemins-publics` |
| `deploy-docker-app.yaml` | **push sur `main`** touchant `ansible/roles/**` ou un playbook d'hôte ; ou à la main | déduit les tags des rôles modifiés (`resolve_docker_tags.py`), monte le tunnel OLM, lance le(s) playbook(s) sur les vrais hôtes |
| `ping.yaml` | à la main | teste le tunnel OLM de la CI |

- **Merger = déployer.** Le ruleset `main` (`tofu/github/ruleset_homelab.tf`)
  exige une PR et les checks `Ansible lint`, `OpenTofu lint`, `Tests` et
  `CI lint` ; le rôle admin peut contourner (correctif urgent).
- Les secrets du déploiement sont dans l'environnement GitHub `production`,
  lisible depuis `main` seulement (`tofu/github/environments.tf`).
- La CI ne lance **jamais** `tofu apply` : l'infra et le routage Pangolin
  s'appliquent à la main.
- Renovate : épingle les images par digest ; seules les versions de
  `planning-equipes` et de `promptoramix` fusionnent seules
  (`renovate.json`) ; les montées majeures de bases attendent une case cochée
  sur le Dependency Dashboard.

## Les sauvegardes

```mermaid
flowchart LR
  subgraph host["Chaque hôte (docker, pi, pangolin, flip)"]
    timer["borgmatic.timer<br/>01:00"] --> bm["borgmatic (root)<br/>/etc/borgmatic.d/app.yaml"]
    bm -- "dump dans le conteneur" --> db[("Postgres / MariaDB")]
    bm -- "sqlite3 .backup" --> sq["/var/lib/borgmatic-sqlite/app"]
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
  hôte compromis efface ses dépôts.
- Rétention Borg : 7 quotidiennes, 4 hebdomadaires, 6 mensuelles, 1 annuelle.
- Un modèle unique, `ansible/roles/borgmatic/templates/app.yaml.j2`, appelé
  par chaque rôle via `include_role: borgmatic tasks_from=app.yml`.
- Restauration : [runbooks/sauvegarde-et-restauration.md](runbooks/sauvegarde-et-restauration.md)
  et [backup-restore.md](backup-restore.md).

## La supervision (Beszel)

Uptime Kuma dit si une appli répond et si ses sauvegardes passent ; Beszel
dit comment vont les hôtes : CPU, mémoire, disques, réseau, conteneurs, et
S.M.A.R.T. là où il y a des disques physiques. Un hub (rôle `beszel`, VM
docker, `monitoring.sylvain.cloud` derrière le SSO puis le compte Beszel) et
un agent par hôte (rôle `beszel_agent`). Les agents ouvrent eux-mêmes une
WebSocket vers le hub : aucun n'écoute de port.

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
  inspect, ni écriture. Newt lit encore le socket directement (suite : #853).
- **Logs des conteneurs** : la fiche d'un conteneur dans l'interface
  (`CONTAINER_DETAILS=true` côté hub) montre ses 200 dernières lignes,
  demandées à l'agent à chaque ouverture et jamais stockées dans le hub. Tout
  compte Beszel qui voit le système les lit, et sur le LAN ce compte est la
  seule barrière : un token ou un mot de passe qu'une appli écrit dans ses
  logs y devient lisible. L'onglet inspect de la même fiche reste vide : le
  proxy le refuse (403 dans ses logs à chaque ouverture), parce que l'agent
  n'en retire que les variables d'environnement, pas les arguments de
  commande (le `--requirepass` du redis de nextcloud) ni les labels. Sur le
  LXC newt et l'hôte Proxmox (agent binaire, sans Docker), seuls les logs des
  services systemd suivis (`SERVICE_PATTERNS`).
- **Lancement** : `dc@beszel_agent` (unité user) sur docker, pi et flip ;
  `dc@beszel_agent` en unité système sur le NAS (`nas.yml`, à la main) ;
  `docker compose up -d` et la restart policy sur Pangolin (pas de
  `docker_service`) ; un service systemd sur le LXC newt (`lxc.yml`, à la
  main) et sur l'hôte Proxmox (`pve.yml`, à la main, en root sans become :
  pas de sudo sur l'hôte), qui lit aussi le S.M.A.R.T. de `sda`, le SSD M.2
  SATA qui porte toutes les VM et le LXC (`CAP_SYS_RAWIO`, groupe `disk` et
  `DeviceAllow=/dev/sda r` dans l'unité). L'hôte Proxmox n'a que cet agent : ni `00-setup`, ni
  `security`.
- **Alertes** (disque > 85 %, mémoire, swap, hôte muet) : réglées dans
  l'interface, envoyées par e-mail (SMTP Infomaniak réglé dans l'interface
  du hub). Elles vivent dans la base du hub, sauvegardée par borgmatic. Si la
  VM docker tombe, Beszel se tait : Uptime Kuma (hors VM) le voit par le
  moniteur `Healthcheck Beszel`.
- **Limites connues** : sur le Pi, la mémoire par conteneur reste vide tant
  que le contrôleur cgroup mémoire est coupé (issue #846) ; son S.M.A.R.T.
  passe par un pont USB RTL9210 (`-d sntrealtek`), non vérifié avant
  déploiement ; le LXC newt (non privilégié) ne voit ni S.M.A.R.T. ni
  capteurs fiables, mais son CPU, sa mémoire, son disque et `newt.service`.
- **Hors périmètre** : l'hôte Proxmox, seul à voir le disque rotatif de la VM
  docker (#852).
