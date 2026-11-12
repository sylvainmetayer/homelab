# Renommer le tableau de bord Pangolin en hall.sylvain.cloud

Procédure, pas un incident : `pangolin.sylvain.cloud` devient `hall.sylvain.cloud`
pour le **tableau de bord** (pages, connexion, lien de retour de Pocket ID).
`pangolin-api.sylvain.cloud` ne change pas. L'**ancien nom reste servi** pour
l'API et le WebSocket que les Newt et OLM déjà installés utilisent, et pour le
SSH (`ssh sylvain@pangolin.sylvain.cloud`, `ansible/known_hosts`, CI) : les
tunnels migrent plus tard, un par un. À faire avec Sylvain présent, un jour
ouvré entre 08:00 et 19:00 (Paris), de préférence depuis le LAN.

Ce qui a été éprouvé sur un banc (podman, mêmes images que le rôle, Newt 1.20.0)
et ce qui ne l'a pas été : voir [README du rôle](../../ansible/roles/pangolin/README.md), section « Renommage du tableau de bord ».
Non éprouvés : un vrai navigateur (cookie, boucle de connexion), un aller-retour
complet avec le vrai Pocket ID, OLM (runners CI), le Newt Windows de la famille,
la durée réelle de la coupure.

## Les deux PR, dans cet ordre

1. **PR 1** (`tofu/pangolin_config`, additive) : `pocketid_client.pangolin`
   accepte les URL de retour des deux noms. Aucun effet au merge.
2. **PR 2** (brouillon, « NE PAS FUSIONNER sans Sylvain ») : le rôle `pangolin`
   (`pangolin_dashboard_url` = hall, `pangolin_dashboard_legacy_url` = pangolin,
   `pangolin_gerbil_endpoint` = pangolin), le moniteur Uptime Kuma, le lanceur
   Pocket ID, Homepage, les docs. **Son merge déploie le rôle `pangolin` en
   production.**

## Avant (la veille ou le matin)

1. `dig +short hall.sylvain.cloud` donne l'IP de Pangolin (A joker de
   `tofu/dns`) ; rien d'autre à créer, le joker Let's Encrypt `*.sylvain.cloud`
   couvre `hall.`.
2. Merger la PR 1, puis l'appliquer (skill `pangolin-config-plan` : worktree
   sur `origin/main`, `plan`, lecture, `apply`). Le plan doit montrer **une
   seule mise à jour en place** : `pocketid_client.pangolin`, `callback_urls`
   passe d'une URL à deux. Autre chose : s'arrêter et lire (le plan de ce
   module peut porter des changements en attente, apply par `-target` après
   lecture de `plan -target`).
3. Vérifier dans Pocket ID (Administration, clients, Pangolin) que les deux
   adresses `https://hall…/auth/idp/<id>/oidc/callback` et
   `https://pangolin…/auth/idp/<id>/oidc/callback` y sont, et que la connexion
   par passkey sur `https://pangolin.sylvain.cloud` marche encore.
4. Noter les Newt et OLM en ligne (Pangolin, onglet Sites ; runners CI), pour
   les comparer après. Aucune autre PR à fusionner pendant l'opération
   (Renovate compris : un merge de plus lance un déploiement de plus).
5. Rebaser la PR 2 sur `main` (le commit de la PR 1 est reconnu et sauté),
   attendre la CI verte, la sortir du brouillon.

## Le jour J

1. **Merger la PR 2** (`gh pr merge --rebase --delete-branch`). Le push lance
   `deploy-docker-app` (hors 19:00-08:00, sinon il est annulé : un
   `workflow_dispatch` est immédiat). Il déploie : le play `pangolin` entier
   (`host_vars/pangolin` change), `homepage` et `docs_site` sur docker.
2. Dans le play `pangolin`, le rôle écrit `dynamic_config.yml` (Traefik le
   relit sans redémarrer : les routeurs de hall apparaissent d'abord), puis
   `config.yml` et force le handler `Restart Pangolin service` :
   `docker compose down` puis `up -d`, qui **recrée toute la pile** (pangolin,
   gerbil, traefik, crowdsec). **Coupure attendue** : tous les accès publics,
   tableau de bord compris, le temps que Pangolin redevienne sain (non
   chronométrée en production) ; les Newt se reconnectent seuls (banc : environ
   30 s après le retour de la pile). Le play `flip` passe par le SSH direct de
   Pangolin, pas par le tunnel : il n'est pas coupé.
3. **Vérifier**, dans cet ordre :
   - `ssh sylvain@pangolin.sylvain.cloud` puis `cd /opt/pangolin && docker compose ps` :
     pangolin healthy, gerbil et traefik Up (`docs/runbooks/pangolin-injoignable.md` sinon) ;
   - `curl -sSI https://hall.sylvain.cloud | head -1` répond, certificat joker ;
   - `curl -sSI https://pangolin.sylvain.cloud/ | head -3` : `302` vers
     `https://hall.sylvain.cloud/` ; `curl -sSI https://pangolin.sylvain.cloud/api/v1/`
     : réponse de l'API (200 sur le banc), pas de redirection ;
   - connexion de Sylvain **par passkey** sur `https://hall.sylvain.cloud`
     (navigateur propre) : c'est le test que le banc ne fait pas ; ouvrir aussi
     une ressource protégée (redirigée vers `hall…/auth/resource/…`) ;
   - un Newt de **chaque site** en ligne (docker, pi, LXC, flip, NAS si l'un en
     a un) et les ressources privées (`docker-apps.internal`) ;
   - le déploiement a fini vert, y compris les plays `pangolin` puis `flip` : la
     CI joint encore l'hôte (SSH `pangolin.sylvain.cloud`) et le tunnel OLM ;
   - les moniteurs Uptime Kuma d'applis repassent au vert (les rouges passent
     une minute pendant la coupure).
4. **Appliquer la partie Tofu de la PR 2**, après le déploiement (sinon le
   moniteur sonderait un nom pas encore servi) : `plan` de
   `tofu/pangolin_config` attendu : `uptimekuma_monitor_http.pangolin_dashboard`
   (URL vers hall) et `pocketid_client.pangolin` (`launch_url` vers hall) mis à
   jour en place, `uptimekuma_monitor_http.pangolin_dashboard_legacy_api`
   créé (ancien nom, `/api/v1/`). `pangolin_idp` : aucun changement (un diff
   sur lui est inattendu).

## Retour arrière

Par **SSH direct sur la VM** (`ssh sylvain@pangolin.sylvain.cloud`, clé et IP
publique, le mur SSO n'y est pour rien) ; console Hetzner si le SSH ne répond pas.

- **Propre** (un déploiement, même coupure) : PR de revert de la PR 2 (ou, dans
  `host_vars/pangolin/variables.yaml`, `pangolin_dashboard_url` de nouveau
  `pangolin.…`, `pangolin_dashboard_legacy_url: ""`, `pangolin_gerbil_endpoint`
  retiré), merge, `workflow_dispatch` si on est hors fenêtre. Le moniteur et le
  lanceur Pocket ID suivent par un `apply` du revert.
- **Urgence à la main** (le revert propre suit, sinon le prochain déploiement
  remet hall) : `sudo` sur la VM, dans `/opt/pangolin/config/config.yml`,
  `app.dashboard_url` à `https://pangolin.sylvain.cloud` et `server.cors.origins`
  à cette seule adresse, puis `sudo systemctl restart pangolin`. Les Newt se
  reconnectent seuls.
- **Seule la redirection pose problème** : dans
  `/opt/pangolin/config/traefik/dynamic_config.yml`, retirer le routeur
  `legacy-dashboard-router` (Traefik relit le fichier sans redémarrage ; un
  fichier invalide est refusé en entier, certificats compris : regex en guillemets
  simples). Sans ce routeur, la connexion boucle de nouveau sur l'ancien nom :
  n'ouvrir les pages que par hall, le revert propre est le vrai correctif. Vider `pangolin_dashboard_legacy_url` n'est **pas** le bon geste :
  il retire aussi l'accès des Newt par l'ancien nom.
- Pocket ID : rien à défaire, les deux URL de retour y restent. Les sessions
  ouvertes sous hall ne servent plus sur l'ancien nom (cookie d'un autre
  domaine) : tout le monde se reconnecte, rien d'autre ne se perd.

## La suite (autres PR, au calme)

1. Migrer les clients vers hall, **un par un**, en vérifiant chaque site en ligne :
   `newt_endpoint` (`ansible/group_vars/all/variables.yml`, commun : le passer à
   hall touche tous les Newt Ansible d'un coup, donc à découper par hôte si on
   veut un par un), l'action `olm-tunnel` et le workflow de déploiement (OLM,
   `ansible_host` et ProxyJump du SSH peuvent garder l'ancien nom), les fiches de
   support à distance de la famille (`support-a-distance-famille*.md`, poste
   Windows : endpoint écrit dans un fichier de la famille, à refaire sur place).
2. `pangolin_gerbil_endpoint` vers hall seulement quand plus rien n'a besoin de
   l'ancien nom, puis retirer l'ancien : `pangolin_dashboard_legacy_url`, le
   moniteur `pangolin_dashboard_legacy_api`, la seconde URL de
   `callback_urls` et `pangolin_dashboard_legacy_host` (`pocket_id.tf`). Un
   enregistrement DNS suffit à garder `pangolin.` pour le SSH et `known_hosts`.
3. `tofu/pangolin` (autre sujet, non touché ici) : `terraform.tfvars`
   `dashboard_url` à passer à hall (valeur donnée au `templatefile` du
   cloud-init `user_data.yaml`, qui ne la lit pas aujourd'hui ; `user_data` est
   dans `ignore_changes`, aucun remplacement de VM). Aucune occurrence du nom dans
   `flip.tf` ni dans le banc `drill`.
