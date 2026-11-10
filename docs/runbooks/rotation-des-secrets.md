# Rotation planifiée des secrets

Procédure, pas un incident. Chaque clé des deux fichiers SOPS
(`secrets/secrets.sops.yaml` pour Tofu et mise, `secrets/ansible.sops.yaml`
pour les playbooks) a son entrée dans `secrets/secrets-rotation.yaml` : les
trois vivent dans le dépôt privé `homelab-secrets`, monté en sous-module à
`secrets/` ([ADR 0018](../adr/0018-secrets-depot-prive.md)). Sa nature
(`kind`), la date de sa dernière rotation (`last_rotated`) et le lien vers
ses étapes ci-dessous (`how`). Plus bas, « fichier racine » désigne
`secrets/secrets.sops.yaml` (à la racine du dépôt jusqu'au 30/10/2026).

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

  `<fichier>` est celui de l'entrée (`file`), commande lancée depuis la
  racine de `homelab` (qui porte `.sops.yaml`). `sops set` ne re-chiffre que
  cette clé : `git -C secrets diff` ne montre qu'elle, plus `mac` et
  `lastmodified`.
- **Créer le nouveau, basculer, vérifier, révoquer l'ancien.** Un jeton
  révoqué avant que la bascule soit vérifiée coupe Tofu, la CI ou une appli.
- **Sylvain applique lui-même** (`tofu apply`, `ansible-playbook` sans
  `--check`). Merger sur `main` un changement d'`ansible/roles/**` ou d'un
  playbook déploie ; un changement du seul fichier SOPS ne déploie rien :
  le playbook se lance à la main.
- **Puis la date.** Dans `secrets/secrets-rotation.yaml`, l'entrée de chaque
  clé tournée : `last_rotated` à la date du jour, `estimated: false`, dans le
  même commit que le fichier SOPS (`chore(secrets): rotation de …`), commit
  **dans le sous-module**, poussé sur le `main` de `homelab-secrets`, puis
  le bump du sous-module dans `homelab`, par une PR :

  ```bash
  git -C secrets switch main && git -C secrets pull --ff-only   # avant sops set
  git -C secrets commit -am "chore(secrets): rotation de …" && git -C secrets push
  git add secrets && git commit -m "chore(secrets): rotation de …"   # branche de PR
  ```

  La CI (Lint, déploiement, échéances) lit le commit qu'épingle `homelab` :
  avant le merge du bump, le moniteur reste « down » et le déploiement lit
  l'ancienne valeur. Le lundi suivant le merge, il repasse « up » si plus
  rien n'est dû.

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
  supprimer l'ancien jeton. Le même jeton nourrit le rapport des coûts
  (rôle `cost_report`) : `ansible-playbook docker.yml --tags cost_report`,
  puis `sudo systemctl start cost-report` sur la VM docker, et Hetzner ne
  doit pas être « en erreur » dans `journalctl -u cost-report`.

### OVH

Quatre applications d'API distinctes, chacune un triplet
application key / application secret / consumer key :

- `OVH_APPLICATION_KEY`, `OVH_APPLICATION_SECRET`, `OVH_CONSUMER_KEY`
  (fichier racine) : le provider ovh de `tofu/dns`, `tofu/s3_state`,
  `tofu/keepass_backup`, `tofu/ref`, `tofu/site`, `tofu/1y` et
  `tofu/planning`.
- `nas_ovh_application_key`, `nas_ovh_application_secret`,
  `nas_ovh_consumer_key` (fichier Ansible) : le défi DNS-01 de Let's Encrypt
  du Traefik du NAS (`nas_proxy`).
- `pangolin_ovh_application_key`, `pangolin_ovh_application_secret`,
  `pangolin_ovh_consumer_key` (fichier Ansible) : le défi DNS-01 des jokers
  `*.sylvain.cloud` et `*.sylvain.dev` du Traefik de Pangolin (ADR 0031),
  restreinte à `POST record`, `POST refresh` et `DELETE record/*` des deux
  zones (lien `createToken` prérempli dans `ansible/roles/pangolin/defaults/main.yml`).
  Après la rotation : `ansible-playbook pangolin.yaml --tags pangolin`
  (redémarre la pile), puis révoquer l'ancienne. Elle ne sert qu'à l'émission
  et au renouvellement : une clé cassée ne se voit qu'au renouvellement suivant
  (`docker logs traefik 2>&1 | grep -i acme`).
- `costs_ovh_application_key`, `costs_ovh_application_secret`,
  `costs_ovh_consumer_key` (fichier Ansible, optionnelles) : le rapport des
  coûts (rôle `cost_report`, VM docker), en lecture seule des factures et
  de la consommation Public Cloud : `GET /me/bill`, `GET /me/bill/*`,
  `GET /cloud/project/<projet>/usage/current`, rien d'autre. Création (lien
  `createToken` prérempli) et vérification :
  [ansible/roles/cost_report/README.md](../../ansible/roles/cost_report/README.md),
  section « OVH ».
  Avec `costs_ovh_cloud_project_id` (`identifier`, jamais tournée :
  l'identifiant du projet, le même que `OVH_CLOUD_PROJECT_ID`).

Créer une nouvelle application avec les **mêmes droits** que l'ancienne
(les relire avant : console OVH, ou `GET /me/api/credential` dans la
console d'API), basculer les trois clés ensemble par `sops set`, puis :
pour la première, un `plan` vide dans chacun des modules cités ; pour la
seconde, `ansible-playbook nas.yml --tags nas_proxy` et un renouvellement
de certificat réussi dans les logs de `nas-proxy` ; pour la troisième,
`ansible-playbook docker.yml --tags cost_report`, puis
`sudo systemctl start cost-report` sur la VM docker : OVH ne doit être ni
« en erreur » ni « non configurée » dans `journalctl -u cost-report`.
Révoquer ensuite l'ancienne application (`DELETE /me/api/application/{id}`).

#### Consumer key de Tofu : `ovh_credentials.py`

Pour `OVH_CONSUMER_KEY`, `.github/scripts/ovh_credentials.py` fait le
travail. Il lit `OVH_APPLICATION_KEY`, `OVH_APPLICATION_SECRET`,
`OVH_CONSUMER_KEY`, `OVH_CLOUD_PROJECT_ID` et `home_ip` dans
l'environnement que mise charge depuis le fichier racine. Il n'affiche,
n'écrit sur disque ni ne passe en argument aucun secret. La nouvelle
consumer key va de la réponse de l'API à l'entrée standard de
`sops set --value-stdin`, sans passer par le terminal. Toute réponse de
forme inattendue fait échouer la commande sans rien révoquer.

**Règles du jeton de Tofu.** Elles sont dans `access_rules()` du script,
relues en PR. Ce sont les routes que le provider `ovh` 2.24.0 appelle pour
les ressources des modules, lues dans son source :

- `GET /auth/details`, appelée au démarrage du provider (`ovh/config.go`,
  `authenticate()`). Si elle est refusée, chaque `plan` échoue.
  `GET /auth/time` est sans authentification et ne demande pas de règle.
- `GET /auth/currentCredential` : le jeton lit son propre identifiant, et
  le script sait ainsi lequel est en cours. Il ne lit rien d'autre.
- Pour chacune des quatre zones (`sylvain.cloud`, `sylvain.dev`,
  `sylvainmetayer.fr`, `metayer.dev`) :
  - `/domain/zone/<zone>/record` en `GET` et `POST`, `record/*` en `GET`,
    `PUT` et `DELETE` ;
  - `POST /domain/zone/<zone>/refresh` ;
  - `/domain/zone/<zone>/redirection` et `redirection/*`, mêmes méthodes.
- Pour le projet Public Cloud :
  - `GET /cloud/project/<projet>/role` ;
  - `/cloud/project/<projet>/user` en `GET` et `POST`, `user/*` en `GET`,
    `POST`, `PUT` et `DELETE` (utilisateurs S3, leurs clés, leurs
    politiques) ;
  - `/cloud/project/<projet>/region/*` en `GET`, `POST`, `PUT` et `DELETE`
    (buckets et cycle de vie). C'est un joker par région : le projet n'a
    pas de route plus étroite pour les buckets.

  Le jeton n'a aucun droit sur le reste du projet (instances, réseau,
  facturation).

Le test échoue si un module touche une autre zone, prend une autre
ressource ou data source `ovh`, ou change de version de provider : dans ce
cas, relire les routes dans le source du provider avant de monter la
version.

Le jeton de Tofu n'a aucune route `/me/api/…` : il ne peut ni lister ni
révoquer d'identifiant, donc ni ceux du NAS, de Pangolin ou de Proxmox. Pour
cela, `list` et `revoke` demandent un **identifiant temporaire**
(`POST /auth/credential`, non signé : la clé d'application suffit). Il est
limité à `GET /auth/currentCredential`, `GET /me/api/credential`,
`GET /me/api/credential/*` et `POST /auth/logout`, plus
`DELETE /me/api/credential/*` pour `revoke`. L'outil affiche son URL de
validation : la valider avec la durée la plus courte proposée, puis appuyer
sur Entrée. La clé reste en mémoire le temps de la commande. Elle n'est
écrite ni dans SOPS ni sur disque. À la fin, l'outil l'expire par
`POST /auth/logout`, même après une erreur ou un Ctrl-C. Si l'outil est tué
avant :
- un identifiant jamais validé expire seul ;
- un identifiant validé vit jusqu'à la fin de la durée choisie. `list` le
  montre (marque `t` quand c'est le sien) ; le supprimer dans la console
  OVH.

**Restriction par IP.** Le jeton est limité à l'IP de la maison
(`allowedIPs`, `home_ip` en `/32`, ou `/128` en IPv6). Tofu ne tourne
jamais en CI avec cette clé. Un `plan` lancé ailleurs est refusé : il n'y a
rien à passer au plan. Pour travailler depuis un autre réseau, refaire un
jeton par `renew --allowed-ip <bloc>` (option répétable), puis valider,
vérifier et révoquer comme ci-dessous. Si l'IP de la maison change (box
remplacée, opérateur, maison perdue), Tofu est coupé. `renew` marche alors
de n'importe où, puisqu'il ne demande que la clé d'application : mettre
`home_ip` à jour, ou passer `--allowed-ip`, puis suivre le pas à pas.
([bbox-remplacee.md](bbox-remplacee.md),
[perte-totale-maison.md](perte-totale-maison.md) renvoient ici.)

##### Ne jamais révoquer

Le compte OVH porte d'autres applications que celle de Tofu. Leurs
identifiants n'ont rien à voir avec cette rotation :

- `pangolin_ovh_*` : DNS-01 des jokers sur Pangolin (jeton du 09/11/2026) ;
- `nas_ovh_*` : DNS-01 du Traefik du NAS (jeton du 10/11/2026, PR #1355) ;
- le plugin ACME de Proxmox (certificat de `pve.sylvain.cloud`, « ACME
  DNS-01 OVH, configuré sur le nœud », `tofu/proxmox/provider.tf`), hors
  SOPS. Le suivi du mainteneur cite une application `proxmox-acme`, et
  aussi l'usage de `nas_ovh_*` par ce plugin. Le dépôt ne dit pas quel
  jeton il utilise : **à vérifier sur le nœud avant toute révocation.**
  Dans Datacenter → ACME → Challenge Plugins, ouvrir le plugin OVH et
  relever `OVH_AK`, l'application key : ce n'est pas le secret, mais ne
  rien copier hors du poste. Dans la console OVH (identifiants d'API), la
  comparer aux applications que `list` marque hors rotation.
- `costs_ovh_*` : rapport des coûts.

Garde-fous de l'outil :
- `list` affiche tous les identifiants du compte, chacun avec le nom et la
  description de son application. Ceux des autres applications sont
  marqués `[AUTRE APPLICATION, hors rotation]`.
- `revoke` refuse tout identifiant qui n'appartient pas à l'application de
  `OVH_APPLICATION_KEY`. Les deux `applicationId` doivent être des
  entiers, et aucune option ne lève ce refus.
- `revoke` refuse aussi, sans `--ignore-recent-use`, un identifiant dont la
  dernière utilisation est postérieure à la création de l'identifiant en
  cours : un autre système s'en sert encore.
- `revoke` ne révoque qu'un identifiant à la fois.

Les jetons des autres applications se tournent à la main, comme décrit plus
haut.

##### Pas à pas

Depuis la racine de `homelab`, sous-module `secrets/` sur `main` à jour et
sans modification (`git -C secrets status`) :

1. Lancer `mise exec -- python3 -I .github/scripts/ovh_credentials.py list`
   et valider l'identifiant temporaire. La liste donne l'application, l'état,
   les dates, les IP et les règles de chaque identifiant. `*` marque celui
   en cours : noter son id. Seuls les identifiants `[rotation]` sont
   concernés.
2. Lancer `mise exec -- python3 -I .github/scripts/ovh_credentials.py renew`.
   L'outil demande l'identifiant, range la consumer key dans
   `secrets/secrets.sops.yaml` (`OVH_CONSUMER_KEY`, non commitée), puis
   affiche l'URL de validation. Si `sops` échoue, l'URL n'est pas affichée :
   l'identifiant reste en attente puis expire seul. Relancer `renew`.
3. Ouvrir l'URL, se connecter au compte OVH, choisir la durée de validité
   proposée et valider. Aucune API ne fait cette étape. Tant qu'elle n'est
   pas faite, Tofu échoue avec la clé rangée.
4. Vérifier qu'un plan est vide dans chaque module :
   - `mise run plan` (`tofu/pangolin` déclare le provider) ;
   - `mise run plan-ref` et `mise run plan-planning` ;
   - `mise exec -- tofu -chdir=tofu/<module> plan` pour `dns`, `s3_state`,
     `keepass_backup`, `site` et `1y`.
5. **Retour arrière** si un plan échoue (droit manquant, IP) :
   1. Lancer `git -C secrets restore secrets.sops.yaml`. Rien n'est encore
      commité, donc le fichier revient à l'ancienne clé, toujours valide
      chez OVH. Vérifier qu'un plan repasse.
   2. Révoquer le nouvel identifiant :
      `revoke <nouvel id> --ignore-recent-use`. Il vient de servir, d'où
      l'option.
   3. Corriger `access_rules()` par PR avant de recommencer.
6. Relancer `list` : le nouvel identifiant doit porter `*` et être
   `validated`.
7. Lancer `mise exec -- python3 -I .github/scripts/ovh_credentials.py revoke <ancien id>`,
   valider l'identifiant temporaire (avec `DELETE`), puis taper l'id pour
   confirmer (`--yes` saute cette confirmation). L'outil refuse :
   - l'identifiant en cours, sans `--force-current` ;
   - un identifiant utilisé après la création de l'actuel, sans
     `--ignore-recent-use` ;
   - un identifiant d'une autre application, toujours (« Ne jamais
     révoquer »).
8. Mettre la date de `OVH_CONSUMER_KEY` dans `secrets-rotation.yaml`, puis
   faire le commit et le bump comme dans « Règles communes ».

Reste manuel : `OVH_APPLICATION_KEY` et `OVH_APPLICATION_SECRET`. L'API ne
crée pas d'application (`/me/api/application` ne fait que `GET` et
`DELETE`). Pour les tourner, créer une application sur
`https://eu.api.ovh.com/createApp/`, passer les deux valeurs par `sops set`,
lancer `renew`, faire les étapes 3 et 4, puis supprimer l'ancienne
application dans la console OVH. Cette suppression révoque tous ses
identifiants.

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

`CLOUDFLARE_API_TOKEN` (fichier racine, `tofu/ref`, `tofu/site`, `tofu/1y`,
`tofu/planning`) : tableau de bord Cloudflare, My Profile → API Tokens,
**Roll** du jeton existant (mêmes permissions, nouvelle valeur), `sops set`,
puis un `plan` vide dans les quatre modules (avec `GITHUB_TOKEN` exporté, voir leurs
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

`pangolin_root_api_key` (même fichier, alias `pangolin.root`, servi au seul
fournisseur d'identité de `pocket_id.tf`) : même chemin dans l'**admin du
serveur**, API Keys, avec les seules actions des fournisseurs d'identité et
de leurs politiques d'organisation, plus « voir une organisation » (la sonde
de démarrage du provider la lit, 403 sinon) ; une clé d'organisation ne peut
pas créer d'IdP.

### Clé API Anthropic (passerelle IA)

`pangolin_ai_anthropic_api_key` (fichier racine, lue par
`tofu/pangolin_config/ai_gateway.tf`) : console Anthropic, workspace de la
passerelle, nouvelle clé. `sops set`, monter le sous-module, `plan` de
`tofu/pangolin_config` (seul `pangolin_ai_provider.anthropic` change), `apply`,
un appel avec une clé virtuelle, puis révoquer l'ancienne clé. Les clés
virtuelles des applis ne changent pas.

## Secrets d'application (tous les deux ans)

### Secret d'appli lu par Ansible

Clé ou jeton qu'un rôle écrit dans le compose ou le `.env` d'une appli
(clés MCP, secrets OIDC, `promptoramix_linkx_secret`,
`pangolin_maxmind_license_key`, `beszel_agent_tokens`,
`dawarich_chibigeo_api_key`, `immich_timelapse_api_key`,
`immich_swipe_api_key`, `immich_kiosk_api_key`…) :

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

`immich_swipe_api_key` : clé d'API d'Immich (compte de Sylvain) qu'Immich
Swipe pose côté serveur ; nom `immich-swipe` et permissions listées dans
`ansible/roles/immich/README.md`. `pi.yml --tags immich` (redémarre la pile
Immich), puis `https://swipe-photos.sylvain.cloud` doit afficher une photo
sans écran de connexion ; supprimer ensuite l'ancienne clé dans Immich.

`immich_kiosk_api_key` : clé d'API d'Immich **en lecture seule** (compte de
Sylvain), nom `immich-kiosk`, permissions listées dans
`ansible/roles/immich/README.md`. `pi.yml --tags immich`, puis
`https://kiosk.sylvain.cloud` doit afficher une photo ; supprimer ensuite
l'ancienne clé dans Immich.

`jellystat_jellyfin_api_key` : clé d'API de Jellyfin (Tableau de bord → Avancé → Clés API, nom `jellystat` ; une clé Jellyfin n'a pas de périmètre, elle
vaut un administrateur), lue par Jellystat pour lire la médiathèque et les
lectures. Le rôle `jellystat` ne déploie rien tant qu'elle manque. Rotation :
`sops set`, puis `ansible-playbook docker.yml --tags jellystat` (redémarre
Jellystat), vérifier qu'une synchronisation passe (Jellystat, Paramètres →
Tâches), puis supprimer l'ancienne clé dans Jellyfin.

`victoria_logs_agent_passwords` (un mot de passe par hôte) aussi : vmauth
(`docker.yml --tags victoria_logs`), puis l'agent de journaux de chaque hôte
changé, faute de quoi ses envois sont refusés (401) jusqu'à son passage.
`victoria_logs_ui_password` sert à l'interface et au contrôle de la clé de CI :
`docker.yml --tags victoria_logs,ci_key_audit`, sinon ce contrôle reçoit des 401
et son moniteur tombe.

### Clé API statique de Pocket ID

`pocket_id_static_api_key`, **la même valeur** dans `ansible.sops.yaml` (le
rôle `pocket_id` la pose en `STATIC_API_KEY`) et dans `secrets.sops.yaml` (le
provider `pocketid` de `tofu/pangolin_config` s'en sert) : droits
d'administration sur Pocket ID. Rotation, dans cet ordre (l'ancienne cesse de
marcher au redémarrage) :

1. `K=$(openssl rand -hex 32)`, puis `sops set` de la clé dans les deux
   fichiers avec `"$K"`, sans l'afficher ; commit dans `homelab-secrets`,
   bump du sous-module.
2. `ansible-playbook pangolin.yaml --tags pocket_id` (redémarre Pocket ID,
   quelques secondes sans login).
3. `tofu plan` de `pangolin_config` : vide, ce qui prouve que la nouvelle clé
   lit l'API.

### Widgets de Homepage

Clés `homepage_*` de `secrets/ansible.sops.yaml`, lues par le rôle
`homepage` (`defaults/main.yml`, `homepage_link_widgets_extra`). Chacune est
facultative : absente ou vide, son widget n'est pas rendu, le reste de la
page si. Création et rotation suivent le même chemin : créer la valeur dans
l'application (privilège minimal ci-dessous), `sops set` par la commande des
règles communes (`<fichier>` = `secrets/ansible.sops.yaml`), puis
`ansible-playbook docker.yml --tags homepage` et vérifier la carte. Une
clé ajoutée au fichier SOPS reçoit son entrée dans `secrets/secrets-rotation.yaml`
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
| `homepage_calendar_ics_url`, `homepage_calendar_top_nous_ics_url` | Agenda (iCal) : Perso, Top nous | Nextcloud, Agenda → l'agenda → Partager → lien public en lecture seule, puis « Copier le lien d'abonnement » : `webcal://…/remote.php/dav/public-calendars/<jeton>?export`, à enregistrer en `https://` | `application` |
| `homepage_uptimekuma_api_key` | Supervision : Sondes en panne, Sauvegardes, Maintenance (lues par `kuma-summary` dans `/metrics`) | Uptime Kuma, Paramètres → Clés d'API → Ajouter : nom `homepage`, sans expiration ; la clé (`uk<id>_…`) n'est affichée qu'une fois. Une clé d'Uptime Kuma n'ouvre que `/metrics`, en lecture ; tant qu'il en existe une active, `/metrics` refuse le compte administrateur. Rotation : nouvelle clé, `sops set`, déploiement, puis désactiver et supprimer l'ancienne | `application` |
| `homepage_grocy_api_key` | Grocy : à consommer, dates passées, manquants, tâches en retard (lus par `apps-summary`) | Grocy, en admin : Gérer les utilisateurs → Ajouter `homepage` (mot de passe `openssl rand -base64 32`, jamais utilisé), **toutes les permissions décochées** (la lecture de l'API n'en demande aucune) ; se connecter avec ce compte, menu ⚙ → Gérer les clés d'API → Ajouter, type `default`. La clé lit toute la base de Grocy, n'écrit rien | `application` |
| `homepage_papra_api_key` | Papra : documents, ajoutés depuis 7 jours, sans étiquette (lus par `apps-summary`) | Papra, compte de Sylvain, Paramètres → Clés d'API → Créer : permissions **organizations:read** et **documents:read** seules, sans expiration ; la clé (`ppapi_…`) n'est affichée qu'une fois | `application` |
| `homepage_dawarich_api_key` | Dawarich : km du mois, km et pays de l'année (lus par `apps-summary`) | Dawarich, compte de Sylvain, Paramètres → Compte → clé d'API (une seule par compte, qui écrit aussi des points : risque accepté) ; rotation : « Générer une nouvelle clé », puis reconfigurer l'appli mobile qui l'utilise | `application` |
| `homepage_freshrss_api_password` | FreshRSS (lien FreshRSS) : non lus, abonnements | voir ci-dessous : mot de passe d'API du compte `homepage_freshrss_username` (`host_vars/docker`), puis l'API activée dans l'administration, dans cet ordre | `application` |
| `homepage_victoria_logs_password` | Supervision : CrowdSec (alertes 24 h, IP bannies) et Blocky (requêtes et blocages 24 h, Pi et LXC), comptés dans VictoriaLogs | aucune interface : `openssl rand -base64 32` (32 caractères au moins). Le rôle `victoria_logs` en fait le compte vmauth `homepage` (route `/select/logsql/stats_query` seule, flux imposés : conteneur `crowdsec` de Pangolin, `blocky-check.service` du Pi et du LXC newt) : déployer `ansible-playbook docker.yml --tags victoria_logs,homepage`, le compte avant la carte | `application` |

FreshRSS : le rôle `rss` coupe l'API à chaque passage tant que la clé
`homepage_freshrss_api_password` n'existe pas (`rss_api_enabled`). Ordre :

1. FreshRSS, compte de Sylvain, Profil → « Mot de passe de l'API » :
   `openssl rand -base64 32`, enregistrer ; `sops set` de la même valeur.
2. `homepage_freshrss_username: <nom du compte FreshRSS>` dans
   `ansible/host_vars/docker/variables.yaml` (PR).
3. `ansible-playbook docker.yml --tags rss,homepage` : `rss` cesse de couper
   l'API, `homepage` rend le widget.
4. FreshRSS, Administration → Authentification → cocher « Autoriser l'accès
   par API », enregistrer. Avant l'étape 3, le prochain passage de `rss` la
   recouperait.

Pangolin n'ouvre aucun chemin vers `/api/greader.php` : seul ce qui est sur
newt (Homepage) l'atteint sans le SSO. Retrait : supprimer la clé, puis
`--tags rss,homepage` recoupe l'API.

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
(`sops decrypt --extract '["pangolin_api_allowed_ips"]' secrets/ansible.sops.yaml`,
sur le poste) avant de conclure à une mauvaise clé. L'organisation vient de
l'output `homepage_pangolin_org` de `tofu/pangolin_config` (apply requis).

### Compte d'administration d'une appli

Mots de passe des comptes admin (`*_admin_password`, `*_pgadmin_password`,
`beszel_admin_password`…). La plupart des
applis ne lisent ce mot de passe qu'à la création du compte : changer
d'abord le mot de passe **dans l'appli** (son interface, ou sa commande
d'administration), puis `sops set`, puis le playbook du rôle pour que le
compose et le SOPS disent la même chose. `beszel_admin_password` ne sert
plus qu'au premier démarrage du hub : le compte ouvre par Pocket ID, et le
rôle écrit les alertes en superuser (mot de passe dérivé de
`beszel_hub_private_key`, qui le fait suivre à sa rotation).

### ntfy

Les comptes et jetons sont déclarés dans `server.yml` (rôle `ntfy`), que
ntfy relit à chaque démarrage : aucune commande dans l'appli.

- Jeton d'un producteur (`ntfy_scripts_token`,
  `ntfy_github_token`, `ntfy_canary_token`, `ntfy_healthlog_token` dans `secrets/ansible.sops.yaml`, `ntfy_uptime_kuma_token` dans le fichier
  racine) : `printf 'tk_%s' "$(openssl rand -hex 15 | cut -c1-29)"`, puis
  `sops set --value-stdin` (valeur en JSON). Pour `ntfy_uptime_kuma_token`,
  `tofu apply` dans `tofu/pangolin_config` d'abord (la notification Uptime
  Kuma, les alertes de Pangolin de `alerts.tf` et la sortie que relit
  `docker.yml`). Puis
  `ansible-playbook docker.yml --tags ntfy`. Pour `ntfy_scripts_token`, aussi
  `ansible-playbook pve.yml --tags vzdump_restore_test,update_notify` (test
  de restauration vzdump, mises à jour en attente), sans quoi leurs moniteurs
  passent au rouge au passage suivant ; les autres scripts prennent le
  nouveau à la main. Pour `ntfy_github_token` (tout ce que publie la CI),
  `tofu -chdir=tofu/github apply` : secret `NTFY_GITHUB_TOKEN` de
  l'environnement `ntfy-github` (Trivy et bilan Renovate). L'ancien jeton
  cesse de marcher au redémarrage de ntfy.
- `ntfy_sylvain_password` et son hash `ntfy_sylvain_password_hash` changent
  ensemble : `openssl rand`, `htpasswd -niBC 10 x` (mot de passe sur
  l'entrée standard, garder ce qui suit `x:`), `sops set` des deux, le
  playbook, puis le nouveau mot de passe dans l'appli du téléphone.
- `ntfy_publisher_password_hash` : hash d'un mot de passe tiré et jeté (les
  producteurs n'entrent que par jeton) ; le refaire de même, sur incident
  seulement.
- Pocket ID ([pocket-id.md](pocket-id.md)) : `pocket_id_encryption_key`
  (`ansible.sops.yaml`, `encryption`, sur incident seulement) ne se tourne pas à
  la légère, Pocket ID chiffre ses clés de signature avec :
  `encryption-key-rotate` dans le conteneur d'abord, puis la clé SOPS, puis
  `pangolin.yaml --tags pocket_id` (« Secours » de pocket-id.md). Les secrets des clients
  OIDC (Homebox, Pangolin) ne sont pas dans SOPS : ce sont des
  `random_password` de `tofu/pangolin_config/pocket_id.tf`. Les tourner :
  `tofu apply -replace='random_password.pocket_id_client["homebox"]'` (ou
  `["pangolin"]`), puis `docker.yml --tags homebox` pour Homebox ; Pangolin
  reçoit le sien dans le même apply. Beszel (`["beszel"]`) : ressaisir le
  secret dans l'admin PocketBase du hub (`pocket-id.md`), aucun rôle ne le
  relit. Immich (`["immich"]`) et Wishlist (`["wishlist"]`) : idem, ressaisir
  le secret (`tofu output -raw pocket_id_<appli>_client_secret`) dans leur
  interface. Karakeep (`["karakeep"]`), Papra (`["papra"]`), Yamtrack
  (`["yamtrack"]`) et Open WebUI (`["openwebui"]`) : `docker.yml --tags <appli>`, le rôle relit la sortie.
  MediaManager (`["mediamanager"]`) : `nas.yml --tags mediamanager`, à la main
  (jamais par la CI). Jellyfin (`["jellyfin"]`) : `nas.yml --tags jellyfin`, à la
  main (le XML du greffon est réécrit, liens des comptes gardés). Nextcloud (`["nextcloud"]`) : `docker.yml --tags
  nextcloud` (le rôle rejoue `occ user_oidc:provider`). Proxmox
  (`["proxmox"]`) : `pve.yml --tags pve_oidc`, à la main (`pveum realm
  modify` reposé à chaque passage). VictoriaLogs (`["victoria-logs"]`) :
  `docker.yml --tags victoria_logs` (vmauth relit `auth.yml`) ; son secret de
  cookie SSO est dérivé de `backup_passphrase` (pas de clé sops) : une rotation
  de celle-ci ne coupe que les connexions en cours. FreshRSS (`["rss"]`) :
  `docker.yml --tags rss` (clé de session dérivée de `backup_passphrase`).
  BookStack (`["wiki"]`) : `docker.yml --tags wiki`. Actual Budget
  (`["actual"]`) : ressaisir le secret dans son interface.
  Les tuiles vitrine n'ont pas de secret.
- `ntfy_scripts_token` sert aussi au résumé CrowdSec hebdomadaire de Pangolin
  (`/etc/crowdsec-summary/env`) : après sa rotation,
  `ansible-playbook pangolin.yaml --tags pangolin`, aux pièges maison
  (rôle `canary`) : `ansible-playbook 00-setup.yaml --tags canary`, aux traces
  des clés SSH connues (rôle `ssh_login_notify`) :
  `ansible-playbook 00-setup.yaml --tags ssh_login_notify`, sans quoi elles
  échouent en 401 (`journalctl -t ssh-login-notify`), au
  rapport des coûts (`/etc/cost-report.env`, rôle `cost_report`) :
  `ansible-playbook docker.yml --tags cost_report`, sans quoi le rapport du
  1er échoue (HTTP 401, `journalctl -u cost-report`), et au contrôle de la clé
  de CI (rôle `ci_key_audit`) : `ansible-playbook docker.yml --tags ci_key_audit`,
  sans quoi ses alertes ntfy échouent en 401 sans que rien ne le montre avant la
  première (reste le moniteur, donc Telegram).
- `ntfy_canary_token` est dans l'URL du webhook de chaque jeton
  Canarytokens.org : après sa rotation, refaire l'URL
  (`ansible/roles/canary/README.md`, « Webhook vers ntfy ») et la coller
  dans la page de gestion de chaque jeton.
- `ntfy_healthlog_token` est aussi saisi dans HealthLog
  (`/settings/notifications`, carte ntfy) : après sa rotation, l'y recoller et
  envoyer un test. Cinq échecs d'affilée d'ici là coupent le canal : le
  réactiver sur la carte (`ansible/roles/healthlog/README.md`).

### Jetons pièges

`canarytokens` (`secrets/ansible.sops.yaml`, rôle `canary`) : des clés AWS
factices de canarytokens.org, une ou deux par hôte. Rien à protéger en
elles-mêmes ; une clé qui a sonné, ou trop vieille, se remplace : nouveau
jeton sur canarytokens.org (type AWS keys, même mémo, même webhook),
désactiver l'ancien depuis sa page de gestion, `sops set`, puis
`ansible-playbook 00-setup.yaml --tags canary --limit <hôte>`.

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
les rôles qui écrivent ces identifiants, dont `pangolin.yaml --tags pocket_id`). Vérifier par un envoi de test sur
chaque hôte : `printf 'Subject: test msmtp\n\nok\n' | sudo msmtp root`
(`--tags beszel_alerts_test` ne teste que le canal Telegram de Beszel, sans
clés aujourd'hui, et le SMTP de Beszel est réglé dans son interface, pas par
cette clé). Uptime Kuma n'envoie plus de mail (Telegram et
ntfy depuis le 2026-10-29) : ses clés `smtp_user`, `smtp_pass` et
`le_email` ont été retirées du fichier racine.

### Relève e-mail de Papra

`papra_intake_imap_password` (fichier Ansible ; `papra_intake_imap_user`,
l'adresse, est un identifiant) : mot de passe d'application de l'adresse de
relève (Infomaniak, Manager > Service Mail > l'adresse > Mots de passe
d'application). En créer un nouveau, le poser par `sops set --value-stdin`
comme dans les règles communes (fichier `secrets/ansible.sops.yaml`, clé
`papra_intake_imap_password`), puis `ansible-playbook docker.yml --tags
papra`, et révoquer l'ancien. Vérifier :
`sudo systemctl start papra-intake.service` puis
`journalctl -u papra-intake -n 20` (« Relève terminée », pas d'échec de
LOGIN). Détail : `ansible/roles/papra/README.md`.

### Appli développeur Withings (HealthLog)

Hors SOPS et hors inventaire de rotation : le Client ID et le Client Secret
de l'appli Withings (Partner Hub, callback
`https://sante.sylvain.cloud/api/withings/callback`) sont saisis dans
HealthLog (Paramètres → Intégrations → Withings), chiffrés en base, copie
dans KeePassXC. Sur fuite seulement : régénérer le secret dans le Partner
Hub, le recoller dans HealthLog, puis **Déconnecter** et **Connecter
Withings** (nouveaux jetons). Détail : `ansible/roles/healthlog/README.md`.

### Clé API Anthropic (HealthLog)

Hors SOPS et hors inventaire de rotation : la clé est saisie dans HealthLog
(`/settings/ai`, fournisseur Anthropic), chiffrée en base, copie dans KeePassXC
(« Anthropic — HealthLog »). Sur fuite seulement : créer une nouvelle clé dans
la console Anthropic, la coller dans `/settings/ai`, vérifier avec **Tester le
fournisseur actif**, puis révoquer l'ancienne. Détail :
`ansible/roles/healthlog/README.md`, « Claude (API) ».

### Code PIN Immich

`immich_pin` du fichier racine est le PIN de la ressource Pangolin d'Immich
(`tofu/pangolin_config/website_immich.tf`) : nouveau PIN par `sops set`,
puis `tofu apply` de `pangolin_config`. C'est la seule copie : celle du
fichier Ansible, lue par rien, a été retirée le 2026-10-28.

### Code PIN Neonova

`neonova_pin` du fichier racine est le PIN des ressources Pangolin de la démo et
du site d'aide (`tofu/pangolin_config/website_neonova.tf`), donné au client : nouveau PIN par
`sops set`, puis `tofu apply` de `pangolin_config`.

### Secrets du site sylvain.dev

`SITE_PAGES_DEPLOY_HOOK`, `SITE_WEBMENTION_IO_TOKEN`, `SITE_SONAR_TOKEN`
(fichier racine, `tofu/site`) : nouveau deploy hook dans le projet Pages
(puis supprimer l'ancien), nouveau jeton webmention.io, nouveau jeton
SonarCloud (My Account → Security, puis révoquer l'ancien). `sops set`,
`tofu apply` de `tofu/site`, et le build quotidien suivant doit passer.

`SITE_FRESHRSS_OPML_URL` (fichier racine, `tofu/site` : secret Pages
`FRESHRSS_OPML_URL` de production, l'export OPML de FreshRSS lu par la page
« following ») : l'URL porte le jeton de requête de l'utilisateur FreshRSS
(`t=`), à régénérer dans FreshRSS (Configuration → Partage), `sops set`, puis
`apply` de `tofu/site` et un nouveau déploiement Pages. Le jeton d'accès
Pangolin (`rss_site_build_access_token`) se renouvelle à part : `tofu apply
-replace=pangolin_resource_access_token.rss_site_build` dans
`tofu/pangolin_config`, puis `apply` de `tofu/site` (il lit cette sortie).

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
  [mot-de-passe-base.md](mot-de-passe-base.md)). Avant de la changer,
  figer la clé de chiffrement de HealthLog, dérivée d'elle : sans quoi
  HealthLog ne démarre plus (`ansible/roles/healthlog/README.md`,
  « Clé de chiffrement »). Le secret du webhook Withings, dérivé aussi,
  change avec elle : Déconnecter Withings dans HealthLog avant le
  déploiement, Connecter après (la déconnexion désabonne l'URL du secret en
  cours).
- `TF_VAR_state_encryption_passphrase` : chiffre les states de
  `tofu/pangolin`, `tofu/github`, `tofu/s3_state` et `tofu/keepass_backup`.
  `tofu/dns` et `tofu/pangolin_config`, dont le state reste en clair,
  déchiffrent celui de `tofu/pangolin` avec la même passphrase (leur
  `encryption.tf`) : rien à rechiffrer chez eux, mais leur lecture doit suivre
  la rotation, sinon leur plan échoue. Changer de passphrase passe par une
  méthode `fallback` du bloc `encryption` le temps d'un apply par module
  (documentation OpenTofu,
  « State encryption, key rotation »).
- `github_actions_sops_age_key` : voir
  [perte-cle-ou-poste.md](perte-cle-ou-poste.md) ; une nouvelle clé age ne
  protège que les versions futures du fichier, l'historique git reste
  lisible par l'ancienne : tourner aussi ce qu'elle ouvrait.
- Clés de session (`*_session_encryption_key`), secrets serveur
  (`pangolin_secret`, `pangolin_server_secret`) :
  `sops set` d'une valeur `openssl rand`, puis le
  playbook du rôle. Tous les utilisateurs sont déconnectés ; pour Pangolin,
  lire d'abord ce que chiffre son secret serveur dans sa documentation.
- `speedtest_tracker_app_key` : l'`APP_KEY` de Laravel, au format
  `base64:` suivi de 32 octets en base64
  (`valeur="base64:$(openssl rand -base64 32 | tr -d '\n')"`) : sans le
  préfixe, Laravel refuse de démarrer (clé de longueur invalide pour
  AES-256). Puis `docker.yml --tags speedtest_tracker`. Les sessions tombent
  et ce que l'appli a chiffré en base devient illisible : se reconnecter,
  revoir les canaux de notification (Settings > Notifications).
- `monica_v4_app_key`, `monica_v4_hash_salt` : l'`APP_KEY` de Laravel et le
  sel des identifiants hachés de Monica, copiés le 2026-10-31 de l'ancien
  `.env` écrit à la main (date estimée : l'installation). Ne pas les tourner
  sans incident : une nouvelle `APP_KEY` rend illisible ce que Monica a
  chiffré en base et déconnecte tout le monde ; un nouveau sel change les
  identifiants publics. Sur fuite : `sops set` (32 caractères pour
  l'`APP_KEY`), `docker.yml --tags monica`, se reconnecter.

## Vérification

- Le workflow *Secrets rotation*, lancé à la main (`workflow_dispatch`),
  passe au vert et le moniteur « Rotation des secrets » est « up ».
- `git -C secrets log -p secrets-rotation.yaml` : chaque rotation a son commit, avec la
  date et `estimated: false`.
