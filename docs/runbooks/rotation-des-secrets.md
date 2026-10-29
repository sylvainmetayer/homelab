# Rotation planifiée des secrets

Procédure, pas un incident. Chaque clé des deux fichiers SOPS
(`secrets.sops.yaml` pour Tofu et mise, `ansible/secrets.sops.yaml` pour les
playbooks) a son entrée dans [`secrets-rotation.yaml`](../../secrets-rotation.yaml),
à la racine : sa nature (`kind`), la date de sa dernière rotation
(`last_rotated`) et le lien vers ses étapes ci-dessous (`how`).

| Nature (`kind`) | Quoi | Rotation |
|---|---|---|
| `provider` | jetons d'API cloud et fournisseurs : Hetzner, OVH, S3 des states, Cloudflare, Proxmox, clé API Pangolin | chaque année |
| `application` | clés, jetons et mots de passe d'application, comptes d'administration | tous les deux ans |
| `database` | mots de passe de base Postgres, MariaDB, Redis | sur incident seulement |
| `encryption` | clés qui chiffrent des données (passphrase borg, des states, clés de session, secrets serveur, clé age de la CI) | sur incident seulement |
| `identifier` | identifiants, adresses, IP, mentions légales : pas des secrets | jamais |

## Comment l'alerte arrive

- **Lint** (chaque PR) : `.github/scripts/check_secret_rotation.py` échoue
  si une clé d'un fichier SOPS manque à l'inventaire, si une entrée ne
  correspond plus à aucune clé, ou si une entrée est invalide (date
  absente ou future, lien vers une ancre qui n'existe pas). Ajouter un
  secret, c'est donc aussi lui ajouter une entrée ; en retirer un, retirer
  l'entrée.
- **Chaque lundi** (06:30 UTC), `.github/workflows/secrets-rotation.yaml`
  lance le même script avec `--due` : un secret dont l'échéance tombe dans
  les 30 jours, ou est dépassée, fait échouer le run et pousse « down » au
  moniteur Uptime Kuma « Rotation des secrets » (dossier Self-hosted,
  8 jours, notifié sur Telegram et ntfy), avec les noms des clés. Le détail
  (échéance, procédure) est dans le résumé du run. Sans push pendant
  8 jours (workflow désactivé, URL révoquée), le moniteur passe « down »
  aussi.
- En local, depuis la racine : `python3 -I .github/scripts/check_secret_rotation.py --due`
  (sans `PUSH_URL`, rien n'est poussé).

Les dates de la première version de l'inventaire (28/10/2026) sont
**estimées** (`estimated: true`) : le dernier commit qui a changé la valeur
chiffrée de la clé, sans compter les re-chiffrements complets d'un fichier
(changement de destinataires suivi de `sops rotate`, le 05/08/2026 pour le
fichier Ansible, le 22/10/2026 pour le fichier racine), qui changent toutes
les valeurs chiffrées sans toucher aux secrets. Une clé jamais tournée
depuis son ajout porte donc la date de son ajout.

## Règles communes

- **Jamais de valeur à l'écran ni dans un fichier.** Une valeur nouvelle se
  tape sans écho, ou se génère, et passe par l'entrée standard de
  `sops set` :

  ```bash
  read -rs valeur        # collée depuis la console du fournisseur
  # ou : valeur="$(openssl rand -base64 32 | tr -d '\n')"
  printf '%s' "$valeur" \
    | python3 -Ic 'import json, sys; print(json.dumps(sys.stdin.read()))' \
    | sops set --value-stdin <fichier> '["<clé>"]'
  unset valeur
  ```

  `--value-stdin` attend du JSON : `json.dumps` échappe `"` et `\`, qu'un
  `printf '"%s"'` laisserait passer (refus de sops, ou pire, un `\t` lu
  comme une tabulation et une valeur stockée fausse).

  `<fichier>` est celui de l'entrée (`file`). `sops set` ne re-chiffre que
  cette clé : le diff git ne montre qu'elle, plus `mac` et `lastmodified`.
- **Créer le nouveau, basculer, vérifier, révoquer l'ancien.** Un jeton
  révoqué avant que la bascule soit vérifiée coupe Tofu, la CI ou une appli.
- **Sylvain applique lui-même** (`tofu apply`, `ansible-playbook` sans
  `--check`). Merger sur `main` un changement d'`ansible/roles/**` ou d'un
  playbook déploie ; un changement du seul fichier SOPS ne déploie rien :
  le playbook se lance à la main.
- **Puis la date.** Dans `secrets-rotation.yaml`, l'entrée de chaque clé
  tournée : `last_rotated` à la date du jour, `estimated: false`, dans le
  même commit que le fichier SOPS (`chore(secrets): rotation de …`). Le
  lundi suivant, le moniteur repasse « up » si plus rien n'est dû.

## Jetons de fournisseurs (chaque année)

### Hetzner

- `HCLOUD_TOKEN` (fichier racine, lu par le provider hcloud de
  `tofu/pangolin` et par `ansible/inventory/hetzner.py`) : Console Hetzner,
  projet du homelab, Security → API tokens, nouveau jeton **Read & Write**.
  `sops set`, puis `mise run plan` : le plan doit être vide, et
  `ansible-inventory --graph` (depuis `ansible/`) doit toujours lister
  pangolin et flip. Supprimer l'ancien jeton dans la Console.
- `hcloud_readonly_token` (fichier Ansible, secret
  `STORAGE_BOX_QUOTA_HCLOUD_TOKEN` de l'environnement `storage-box-quota`) :
  même écran, permission **Read** seulement, puis `sops set` et
  `tofu -chdir=tofu/github apply` (voir [tofu/github/README.md](../../tofu/github/README.md)).
  Vérifier par un lancement manuel du workflow *Storage Box quota*, puis
  supprimer l'ancien jeton.

### OVH

Deux applications d'API distinctes, chacune un triplet
application key / application secret / consumer key :

- `OVH_APPLICATION_KEY`, `OVH_APPLICATION_SECRET`, `OVH_CONSUMER_KEY`
  (fichier racine) : le provider ovh de `tofu/dns`, `tofu/s3_state`,
  `tofu/keepass_backup`, `tofu/ref`, `tofu/site` et `tofu/1y`.
- `nas_ovh_application_key`, `nas_ovh_application_secret`,
  `nas_ovh_consumer_key` (fichier Ansible) : le défi DNS-01 de Let's Encrypt
  du Traefik du NAS (`nas_proxy`).

Créer une nouvelle application avec les **mêmes droits** que l'ancienne
(les relire avant : console OVH, ou `GET /me/api/credential` dans la
console d'API), basculer les trois clés ensemble par `sops set`, puis :
pour la première, un `plan` vide dans chacun des modules cités ; pour la
seconde, `ansible-playbook nas.yml --tags nas_proxy` et un renouvellement
de certificat réussi dans les logs de `nas-proxy`. Révoquer ensuite
l'ancienne application (`DELETE /me/api/application/{id}`).

### Clés S3 des states

- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (fichier racine, utilisateur
  OVH `tf_state`, lecture-écriture de tous les states) : comme le
  23/10/2026 (`tofu/s3_state/user.tf`), une **nouvelle ressource**
  `ovh_cloud_project_user_s3_credential` (`tf_state_<année>`) à côté de
  l'ancienne et les outputs `s3_access_key`/`s3_secret_key` qui pointent
  dessus, `tofu apply` dans `tofu/s3_state`, `sops set` des deux clés depuis
  `tofu -chdir=tofu/s3_state output -raw …` (jamais affiché : directement
  dans le `printf` de `sops set`), un `plan` vide dans chaque module à
  backend S3, puis la suppression de l'ancienne ressource dans un second
  apply (le backend de `tofu/s3_state` écrit son state avec ces clés-là).
- `state_s3_access_key`, `state_s3_secret_key` (fichier Ansible, utilisateur
  `ansible_state_reader`, lecture du seul state de `pangolin_config`) : même
  méthode sur `tofu/s3_state/user_ansible.tf`, puis un playbook en
  `--check --tags setup` qui lit le state (`ansible/tasks/pangolin_config_outputs.yml`).

### Proxmox

`PROXMOX_TOKEN` (fichier racine, `tofu/proxmox`) : interface Proxmox,
Datacenter → Permissions → API Tokens, nouveau jeton pour le même
utilisateur, **même case « Privilege Separation »** et mêmes permissions
que l'ancien. `sops set` (format `utilisateur@realm!id=secret`),
`mise run plan-proxmox` vide, puis supprimer l'ancien jeton.

### Cloudflare

`CLOUDFLARE_API_TOKEN` (fichier racine, `tofu/ref`, `tofu/site`, `tofu/1y`) :
tableau de bord Cloudflare, My Profile → API Tokens, **Roll** du jeton
existant (mêmes permissions, nouvelle valeur), `sops set`, puis un `plan`
vide dans les trois modules (avec `GITHUB_TOKEN` exporté, voir leurs
README).

`SITE_CF_ANALYTICS_TOKEN` (fichier racine, `tofu/site` : secret Pages
`CF_ANALYTICS_TOKEN` de production, lu par la page « les plus lus ») : même
écran, **Roll** du jeton (mêmes permissions), `sops set`, puis
`apply` de `tofu/site` et un nouveau déploiement Pages pour qu'il soit pris.

### Bot Telegram

`uptimekuma_telegram_bot_token` (fichier racine, notification « Telegram »
d'Uptime Kuma, `tofu/pangolin_config/notifications.tf`) : dans Telegram,
@BotFather → `/mybots` → le bot → **API Token** → **Revoke current token**,
`sops set`, puis `apply` de `tofu/pangolin_config`. Si Beszel utilise le même
bot (`beszel_telegram_bot_token`), le mettre à jour aussi, puis
`docker.yml --tags beszel_alerts`. Le chat id ne change pas.

### Clé API Pangolin

`pangolin_api_key` (fichier racine, provider de `tofu/pangolin_config`) :
interface de Pangolin, organisation, API Keys, nouvelle clé avec les mêmes
permissions. `sops set`, `plan` de `tofu/pangolin_config` vide, puis
supprimer l'ancienne clé dans l'interface.

## Secrets d'application (tous les deux ans)

### Secret d'appli lu par Ansible

Clé ou jeton qu'un rôle écrit dans le compose ou le `.env` d'une appli
(clés MCP, secrets OIDC, `promptoramix_linkx_secret`,
`pangolin_maxmind_license_key`, `beszel_agent_tokens`,
`dawarich_chibigeo_api_key`, `immich_timelapse_api_key`…) :

1. Créer la nouvelle valeur là où elle est émise : `openssl rand` pour un
   secret partagé que le homelab invente ; le service tiers sinon (MaxMind :
   compte, License keys ; Keycloak : `tofu/keycloak_demo_planning_kc`, qui
   produit les secrets OIDC ; Linkx : le secret partagé se change des deux
   côtés en même temps).
2. `sops set`, puis le playbook de l'hôte limité au rôle :
   `ansible-playbook <playbook> --tags <rôle>` (`--check --diff` d'abord,
   sans `-v` : le diff d'un fichier `0600` est masqué).
3. Vérifier l'appli (moniteur Uptime Kuma, un appel du client de la clé),
   puis révoquer l'ancienne valeur chez le tiers.

`beszel_agent_tokens` est un dictionnaire par hôte : le hub
(`docker.yml --tags beszel`) puis l'agent de chaque hôte changé
(`--tags beszel_agent` de son playbook).

`homepage_beszel_password` (superuser PocketBase du widget Beszel de
Homepage) : `openssl rand -base64 32`, `sops set`, puis
`docker.yml --tags beszel,homepage`. Le rôle beszel voit que l'ancien mot de
passe ne se connecte plus et le remplace (`beszel superuser upsert`), le rôle
homepage réécrit sa configuration. Rien à changer dans l'interface.

`victoria_logs_agent_passwords` (un mot de passe par hôte) aussi : vmauth
(`docker.yml --tags victoria_logs`), puis l'agent de journaux de chaque hôte
changé, faute de quoi ses envois sont refusés (401) jusqu'à son passage.
`victoria_logs_ui_password` ne sert qu'à l'interface (vmauth seul).

### Widgets de Homepage

Clés `homepage_*` de `ansible/secrets.sops.yaml`, lues par le rôle
`homepage` (`defaults/main.yml`, `homepage_link_widgets_extra`). Chacune est
facultative : absente ou vide, son widget n'est pas rendu, le reste de la
page si. Création et rotation suivent le même chemin : créer la valeur dans
l'application (privilège minimal ci-dessous), `sops set` par la commande des
règles communes (`<fichier>` = `ansible/secrets.sops.yaml`), puis
`ansible-playbook docker.yml --tags homepage` et vérifier la carte. Une
clé ajoutée au fichier SOPS reçoit son entrée dans `secrets-rotation.yaml`
dans le même commit (`how` : ce paragraphe) ; une rotation révoque l'ancienne
valeur dans l'application une fois la carte vérifiée.

| Clé | Widget | Où la créer, avec quels droits | `kind` |
|---|---|---|---|
| `homepage_proxmox_token_id`, `homepage_proxmox_token_secret` | Proxmox (lien Proxmox) et CPU/mémoire de la VM 100 et du LXC 200 (cartes d'hôte) | voir ci-dessous : utilisateur `homepage@pve`, jeton à séparation de privilèges, rôle `PVEAuditor` sur `/` | `identifier` (`_token_id`, inchangé par une rotation), `provider` (`_token_secret`) |
| `homepage_pangolin_api_key` | Pangolin : sites et ressources | interface de Pangolin, organisation, API Keys : clé d'organisation avec **List Sites** et **List Resources** seulement | `provider` |
| `homepage_speedtest_tracker_token` | Speedtest Tracker : dernier test | interface de Speedtest Tracker, API Tokens : capacité **results:read** seule | `application` |
| `homepage_immich_api_key` | Immich : utilisateurs, photos, vidéos, stockage | Immich, compte **admin** (l'API `/api/server/statistics` l'exige), Account Settings → API Keys : permission **server.statistics** seule | `application` |
| `homepage_jellyfin_api_key` | Jellyfin : médiathèque, lectures en cours | Jellyfin, Tableau de bord → Avancé → Clés API (clé d'administration : risque accepté, `docs/architecture.md`) | `application` |
| `homepage_homebox_password` | Homebox : objets, emplacements, valeur | Homebox : inviter le compte `homepage_homebox_username` (`host_vars/docker`) dans le groupe de Sylvain, mot de passe `openssl rand -base64 32` (le compte peut écrire : risque accepté) | `application` |
| `homepage_karakeep_api_key` | Karakeep : favoris, listes, étiquettes | Karakeep, compte dont on veut les compteurs, User Settings → API Keys (tous ses droits : risque accepté) | `application` |
| `homepage_calendar_ics_url` | Agenda (iCal) | Nextcloud, Agenda → l'agenda → Partager → lien public en lecture seule, puis « Copier le lien d'abonnement » : `webcal://…/remote.php/dav/public-calendars/<jeton>?export`, à enregistrer en `https://` | `application` |

Proxmox (sur l'hôte, en root ; `pveum`, aucun mot de passe : l'utilisateur
n'ouvre pas de session) :

```bash
pveum user add homepage@pve --comment "Widget Homepage, lecture seule"
pveum acl modify / --users homepage@pve --roles PVEAuditor
pveum user token add homepage@pve homepage --privsep 1
pveum acl modify / --tokens 'homepage@pve!homepage' --roles PVEAuditor
```

`token add` affiche le secret une seule fois : `homepage_proxmox_token_id` =
`homepage@pve!homepage`, `homepage_proxmox_token_secret` = la valeur
affichée. Rotation : `pveum user token remove homepage@pve homepage`, puis
les deux dernières commandes et `sops set` du nouveau secret (l'identifiant
ne change pas). Pas dans `tofu/proxmox` : son state n'est pas chiffré, il y
garderait le secret en clair, et Ansible ne lit que celui de
`pangolin_config`.

Pangolin : le widget appelle `https://pangolin-api.sylvain.cloud/v1` depuis
la VM docker, donc depuis l'IP publique de la maison ; l'API d'intégration
est derrière l'allowlist Traefik `int-api-allowlist` (clé sops
`pangolin_api_allowed_ips`) : vérifier que cette IP y est
(`sops decrypt --extract '["pangolin_api_allowed_ips"]' ansible/secrets.sops.yaml`,
sur le poste) avant de conclure à une mauvaise clé. L'organisation vient de
l'output `homepage_pangolin_org` de `tofu/pangolin_config` (apply requis).

### Compte d'administration d'une appli

Mots de passe des comptes admin (`*_admin_password`, `*_pgadmin_password`,
`beszel_admin_password`, `kitchenowl_sylvain_password`…). La plupart des
applis ne lisent ce mot de passe qu'à la création du compte : changer
d'abord le mot de passe **dans l'appli** (son interface, ou sa commande
d'administration), puis `sops set`, puis le playbook du rôle pour que le
compose et le SOPS disent la même chose. `beszel_admin_password` doit rester
le mot de passe du compte admin : le rôle s'en sert pour écrire les alertes
par l'API du hub.

### ntfy

Les comptes et jetons sont déclarés dans `server.yml` (rôle `ntfy`), que
ntfy relit à chaque démarrage : aucune commande dans l'appli.

- Jeton d'un producteur (`ntfy_beszel_token`, `ntfy_scripts_token`,
  `ntfy_github_token` dans `ansible/secrets.sops.yaml`, `ntfy_uptime_kuma_token` dans le fichier
  racine) : `printf 'tk_%s' "$(openssl rand -hex 15 | cut -c1-29)"`, puis
  `sops set --value-stdin` (valeur en JSON). Pour `ntfy_uptime_kuma_token`,
  `tofu apply` dans `tofu/pangolin_config` d'abord (la notification Uptime
  Kuma et la sortie que relit `docker.yml`). Puis
  `ansible-playbook docker.yml --tags ntfy`, et `--tags beszel` pour celui de
  Beszel quand son canal ntfy est allumé. Pour `ntfy_scripts_token`, aussi
  `ansible-playbook pve.yml --tags vzdump_restore_test,update_notify` (test
  de restauration vzdump, mises à jour en attente),
  `ansible-playbook nas.yml --tags update_notify`, sans quoi leurs moniteurs
  passent au rouge au passage suivant ; les autres scripts prennent le
  nouveau à la main. Pour `ntfy_github_token` (tout ce que publie la CI),
  `tofu -chdir=tofu/github apply` : secrets `TRIVY_NTFY_TOKEN` de
  l'environnement `trivy-ntfy` et `RENOVATE_DIGEST_NTFY_TOKEN` de
  l'environnement `renovate-digest`. L'ancien jeton cesse de marcher au
  redémarrage de ntfy.
- `ntfy_sylvain_password` et son hash `ntfy_sylvain_password_hash` changent
  ensemble : `openssl rand`, `htpasswd -niBC 10 x` (mot de passe sur
  l'entrée standard, garder ce qui suit `x:`), `sops set` des deux, le
  playbook, puis le nouveau mot de passe dans l'appli du téléphone.
- `ntfy_publisher_password_hash` : hash d'un mot de passe tiré et jeté (les
  producteurs n'entrent que par jeton) ; le refaire de même, sur incident
  seulement.
- `ntfy_scripts_token` sert aussi au résumé CrowdSec quotidien de Pangolin
  (`/etc/crowdsec-summary/env`) : après sa rotation,
  `ansible-playbook pangolin.yaml --tags pangolin`.

### Identifiants Newt

`newt_docker_client_secret`, `newt_pi_client_secret` (sites créés dans
l'interface, contrairement à flip, proxmox-lxc et nas dont les identifiants
viennent du state de `pangolin_config`) : interface Pangolin, Sites, le
site, régénérer les identifiants. `sops set` de l'id et du secret, puis
`ansible-playbook docker.yml --tags newt` (ou `pi.yml`). Le site est hors
ligne entre la régénération et le redémarrage de Newt : à faire hors des
heures d'usage.

### URL push Uptime Kuma

`*_healthcheck_url` du fichier Ansible : régénérer le jeton push du
moniteur dans Uptime Kuma (ou, pour un moniteur déclaré dans
`tofu/pangolin_config`, le recréer), `sops set`, le playbook du rôle, et
attendre un push « up ».

### Uptime Kuma

`UPTIMEKUMA_PASSWORD` (fichier racine, provider de `tofu/pangolin_config`) :
changer le mot de passe du compte dans Uptime Kuma (Settings → Security),
`sops set`, puis un `plan` vide de `tofu/pangolin_config`.

### Compte SMTP Infomaniak

`pangolin_smtp_pass` (fichier Ansible : msmtp du rôle `security`, Pangolin
et les applis qui envoient des mails) : nouveau mot de passe du compte dans
Infomaniak, `sops set`, puis les playbooks des hôtes (`--tags security`, et
les rôles qui écrivent ces identifiants). Vérifier par un envoi de test
(`--tags beszel_alerts_test`). Uptime Kuma n'envoie plus de mail (Telegram et
ntfy depuis le 2026-10-29) : ses clés `smtp_user`, `smtp_pass` et
`le_email` ont été retirées du fichier racine.

### Code PIN Immich

`immich_pin` du fichier racine est le PIN de la ressource Pangolin d'Immich
(`tofu/pangolin_config/website_immich.tf`) : nouveau PIN par `sops set`,
puis `tofu apply` de `pangolin_config`. C'est la seule copie : celle du
fichier Ansible, lue par rien, a été retirée le 2026-10-28.

### Secrets du site sylvain.dev

`SITE_PAGES_DEPLOY_HOOK`, `SITE_WEBMENTION_IO_TOKEN`, `SITE_SONAR_TOKEN`
(fichier racine, `tofu/site`) : nouveau deploy hook dans le projet Pages
(puis supprimer l'ancien), nouveau jeton webmention.io, nouveau jeton
SonarCloud (My Account → Security, puis révoquer l'ancien). `sops set`,
`tofu apply` de `tofu/site`, et le build quotidien suivant doit passer.

### Mot de passe de sylvain sur les hôtes

`host_user_password_hash` (le mot de passe sudo de `sylvain`) :
`mise run generate_password`, le hash par `sops set`, puis
`ansible-playbook 00-setup.yaml --tags setup`. `pangolin_password` (fichier
racine) est le même genre de hash, posé par cloud-init seulement à la
création de Pangolin (`user_data`, ignoré ensuite) : voir la section
suivante.

### Mot de passe de reconstruction de Pangolin

`pangolin_password` ne sert qu'à une reconstruction de Pangolin
([reconstruction-pangolin.md](reconstruction-pangolin.md)) : le remplacer
par le hash courant de `host_user_password_hash` suffit, aucun apply (le
`user_data` est dans `ignore_changes`).

### Clé du hub Beszel

`beszel_hub_private_key` et `beszel_hub_public_key` vont ensemble : une
nouvelle paire ed25519 générée dans un répertoire temporaire en mémoire
(`/dev/shm`), les deux par `sops set`, puis le hub (`docker.yml --tags
beszel`) et l'agent de **chaque** hôte (`--tags beszel_agent` de docker,
pi, flip, pangolin, lxc, nas et pve) : un agent qui garde l'ancienne clé
publique refuse le hub.

### Bouncer CrowdSec

`pangolin_crowdsec_bouncer_key` : voir [crowdsec.md](crowdsec.md)
(« Rotation de la clé du bouncer »).

## Mots de passe de base (sur incident)

Pas d'échéance : `kind: database`, la date sert de mémoire. La procédure
complète, avec ses pièges (un mot de passe lu à l'initdb seulement), est
dans [mot-de-passe-base.md](mot-de-passe-base.md).

## Clés de chiffrement (sur incident)

Pas d'échéance non plus : les tourner coûte une re-chiffrement ou une
déconnexion, et n'apporte rien sans fuite.

- `backup_passphrase` : chiffre les clés des dépôts borg. Sur fuite,
  `borg key change-passphrase` sur chaque dépôt, puis la nouvelle valeur
  partout où elle est lue (Ansible, environnement `restore-test` par
  `tofu/github`, et les mots de passe dérivés d'elle, voir
  [mot-de-passe-base.md](mot-de-passe-base.md)).
- `TF_VAR_state_encryption_passphrase` : chiffre les states de
  `tofu/pangolin`, `tofu/github`, `tofu/s3_state` et `tofu/keepass_backup`.
  Changer de passphrase passe par une méthode `fallback` du bloc
  `encryption` le temps d'un apply par module (documentation OpenTofu,
  « State encryption, key rotation »).
- `github_actions_sops_age_key` : voir
  [perte-cle-ou-poste.md](perte-cle-ou-poste.md) ; une nouvelle clé age ne
  protège que les versions futures du fichier, l'historique git reste
  lisible par l'ancienne : tourner aussi ce qu'elle ouvrait.
- Clés de session (`*_session_encryption_key`), secrets serveur
  (`pangolin_secret`, `pangolin_server_secret`), `meerkat_crm_jwt_secret`,
  `paperless_secret_key` : `sops set` d'une valeur `openssl rand`, puis le
  playbook du rôle. Tous les utilisateurs sont déconnectés ; pour Pangolin,
  lire d'abord ce que chiffre son secret serveur dans sa documentation.
- `speedtest_tracker_app_key` : l'`APP_KEY` de Laravel, au format
  `base64:` suivi de 32 octets en base64
  (`valeur="base64:$(openssl rand -base64 32 | tr -d '\n')"`) : sans le
  préfixe, Laravel refuse de démarrer (clé de longueur invalide pour
  AES-256). Puis `docker.yml --tags speedtest_tracker`. Les sessions tombent
  et ce que l'appli a chiffré en base devient illisible : se reconnecter,
  revoir les canaux de notification (Settings > Notifications).

## Vérification

- Le workflow *Secrets rotation*, lancé à la main (`workflow_dispatch`),
  passe au vert et le moniteur « Rotation des secrets » est « up ».
- `git log -p secrets-rotation.yaml` : chaque rotation a son commit, avec la
  date et `estimated: false`.
