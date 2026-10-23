# Quiz du homelab

Une banque de questions pour des séances courtes : en tirer cinq ou six, y
répondre sans ouvrir le dépôt, puis vérifier dans le fichier indiqué. Les
réponses sont repliées sous chaque question.

Sections : [Pangolin et ses règles](#pangolin-et-ses-règles) ·
[`dc@` et systemd utilisateur](#dc-et-systemd-utilisateur) ·
[Borgmatic et la Storage Box](#borgmatic-et-la-storage-box) ·
[SOPS et la précédence des variables](#sops-et-la-précédence-des-variables-ansible) ·
[Modules Tofu, states et chiffrement](#modules-tofu-states-et-chiffrement) ·
[La CI et son ruleset](#la-ci-et-son-ruleset)

## Pangolin et ses règles

**1. (QCM)** Dans quel ordre Pangolin évalue-t-il les règles d'une ressource ?

- a) pays, puis chemins publics, puis SSO
- b) garde des antislashs (1), chemins publics (2-9), pays FR/DE (10-11), pays de voyage (20), refus de tout le reste (99), puis SSO
- c) SSO, puis pays, puis chemins

<details><summary>Réponse</summary>

b. Les règles sont lues par priorité croissante, la première qui correspond
gagne. Les chemins publics doivent donc passer *avant* les pays pour valoir
depuis n'importe où. À vérifier : `tofu/pangolin_config/rules.tf` (commentaire
en tête, `country_rule_priority_base`, `travel_country_priority`, `block_country`).
</details>

**2.** Pourquoi la règle des pays FR et DE est-elle un `PASS` et pas un `ACCEPT` ?

<details><summary>Réponse</summary>

`PASS` veut dire « continue vers l'authentification » : la requête doit encore
passer le SSO. Un `ACCEPT` ouvrirait l'appli sans login à toute la France.
`ACCEPT` est réservé aux chemins publics (2-9), protégés par le secret de
l'appli elle-même. À vérifier : `tofu/pangolin_config/rules.tf`.
</details>

**3. (Que fais-tu si…)** Tu pars deux semaines au Japon et tu veux garder
l'accès à tes applis.

<details><summary>Réponse</summary>

Ajouter `JP` avec sa date de fin dans `travel_countries`
(`tofu/pangolin_config/variables.tf`), puis `tofu plan` / `tofu apply` dans
`tofu/pangolin_config`. Le pays reçoit la priorité 20. Le premier apply après
la date le referme ; le check `travel_countries_stale` demande ensuite de
retirer l'entrée. Rien n'applique `pangolin_config` tout seul : sans apply au
retour, il reste ouvert.
</details>

**4.** À quoi sert la règle de priorité 1 qui refuse tout chemin contenant un `\` ?

<details><summary>Réponse</summary>

Pangolin ne normalise pas l'antislash, mais l'appli Node derrière le
transforme en `/`. Sans cette garde, `/api\..\admin` pourrait passer pour un
chemin public autorisé puis atteindre autre chose. Elle est posée sur toute
ressource qui a une règle de chemin (`backslash_guard`). À vérifier :
`tofu/pangolin_config/rules.tf`, test `backslash_guard_covers_every_path_rule`.
</details>

**5. (Que fais-tu si…)** Une PR Renovate qui monte FreshRSS reste bloquée « en attente d'approbation ».

<details><summary>Réponse</summary>

Elle touche `tofu/pangolin_config/path_bypass_images.json` : les chemins
publics de RSS ont été relevés sur une version précise de l'image.
`path-bypass-review.yaml` liste les notes de version et les sources à relire
dans le résumé du run, et attend l'environnement `relecture-chemins-publics`.
Relire, corriger `rss_api_paths` (`website_rss.tf`) dans la même PR si une route
a bougé, puis approuver dans l'interface GitHub.
</details>

**6. (Que fais-tu si…)** Tu as créé une ressource à la main dans l'interface de Pangolin, et le `tofu plan` suivant échoue.

<details><summary>Réponse</summary>

La précondition de couverture de `rules.tf` refuse toute ressource activée
absente de `local.managed_resources` (dérivée de `local.websites`). Soit la
déclarer dans un `website_<app>.tf`, soit la supprimer ou la désactiver dans
Pangolin.
</details>

**7.** Le service est totalement arrêté, et pourtant Pangolin répond `200`. Comment Uptime Kuma s'en aperçoit-il ?

<details><summary>Réponse</summary>

Quand toutes les cibles sont en échec, Pangolin sert sa page de maintenance
(mode `automatic`) avec un code 200. Le moniteur est un
`uptimekuma_monitor_http_keyword` avec `keyword = local.maintenance.title` et
`invert_keyword = true` : trouver le titre de la page de maintenance = DOWN.
À vérifier : `tofu/pangolin_config/maintenance.tf` et `websites.tf`.
</details>

**8. (QCM)** Pour une ressource à plusieurs cibles routées par chemin, quelle priorité donner au fourre-tout `/` ?

- a) la plus haute
- b) la plus basse
- c) peu importe

<details><summary>Réponse</summary>

b, le plus petit numéro. C'est une des deux erreurs déjà livrées une fois
(l'autre : oublier `hc_hostname` sur une `pangolin_target`). À vérifier :
AGENTS.md, test `catch_all_target_has_lowest_priority`
(`tofu/pangolin_config/tests/invariants.tftest.hcl`).
</details>

## `dc@` et systemd utilisateur

**1.** Où tourne `dc@rss`, et sous quel utilisateur ?

<details><summary>Réponse</summary>

C'est une instance du modèle d'unité **utilisateur**
`~/.config/systemd/user/dc@.service` de `sylvain`, avec
`WorkingDirectory=/opt/apps/%i`, donc `/opt/apps/rss`. Le lingering la fait
démarrer au boot sans session ouverte. À vérifier :
`ansible/roles/docker_service/templates/dc@.service.j2` et `tasks/main.yaml`.
</details>

**2. (Que fais-tu si…)** Après `sudo -iu sylvain`, `systemctl --user status dc@rss` répond « Failed to connect to bus ».

<details><summary>Réponse</summary>

La session n'a pas de `XDG_RUNTIME_DIR` : `export
XDG_RUNTIME_DIR=/run/user/$(id -u)`, ou plus simple, se connecter
directement en SSH en tant que `sylvain`. Les scénarios Molecule posent cette
variable pour la même raison (`.config/molecule/config.yml`).
</details>

**3. (QCM)** Le registre Docker est en panne au démarrage de la VM. Les applis déjà déployées démarrent-elles ?

- a) non, `docker compose pull` échoue
- b) oui : seules les images absentes sont téléchargées (`pull --policy missing`), et elles sont déjà là
- c) oui, mais seulement après le retour du registre

<details><summary>Réponse</summary>

b. `ExecStartPre=docker compose pull --policy missing`, puis `up` sans
`--pull`. Les images étant épinglées par digest, une montée de version est une
image absente, donc téléchargée. À vérifier : `dc@.service.j2`.
</details>

**4.** Pourquoi `dc@` arrête-t-il avec `docker compose stop` et pas `down` ?

<details><summary>Réponse</summary>

`down` supprime les conteneurs, et avec eux le contenu des volumes anonymes
(un `VOLUME` de l'image que le compose ne monte pas) au prochain `up`. `stop`
les garde. Pangolin fait l'inverse (`down`), délibérément : tout son état est
en montages bind. À vérifier : `dc@.service.j2`,
`ansible/roles/pangolin/templates/pangolin.service.j2`.
</details>

**5.** Une appli plante en boucle depuis une heure. Est-elle passée en `failed` définitif ?

<details><summary>Réponse</summary>

Non : `StartLimitIntervalSec=0` (jamais d'abandon) et `Restart=always` avec
`RestartSec=15s` fixes, sans backoff. Elle relance `up` toutes les 15 s. À
vérifier : `dc@.service.j2`.
</details>

**6.** Une image suit un tag mobile (`main`) et ne se rafraîchit jamais. Pourquoi, et quoi faire ?

<details><summary>Réponse</summary>

`pull --policy missing` ne retélécharge pas une image déjà présente. Soit
l'épingler par digest (Renovate la fera monter), soit mettre `pull_policy:
always` sur ce service dans son compose (cas du banc Keycloak,
`flip_planning_image_pull_policy`).
</details>

**7. (QCM)** Pangolin est-il une unité `dc@` ?

- a) oui, `dc@pangolin`
- b) non, une unité **système** `pangolin.service` (root), dans `/opt/pangolin`
- c) non, un conteneur lancé à la main

<details><summary>Réponse</summary>

b. `sudo systemctl restart pangolin`. À vérifier :
`ansible/roles/pangolin/templates/pangolin.service.j2`.
</details>

**8.** Pourquoi tout conteneur exposé doit-il être sur le réseau Docker `newt`, et la base sur un autre ?

<details><summary>Réponse</summary>

Newt joint les cibles par leur nom sur ce réseau, et vérifie par le socket
Docker que le conteneur y est (`DOCKER_ENFORCE_NETWORK_VALIDATION=true`). La
base va sur un réseau interne propre à l'appli (`internal: true` sauf
exception) : jamais joignable depuis Newt, donc depuis Pangolin. À vérifier :
`ansible/roles/newt/templates/compose.yaml`, AGENTS.md.
</details>

## Borgmatic et la Storage Box

**1.** Quand les sauvegardes tournent-elles, et que se passe-t-il si l'hôte était éteint à cette heure ?

<details><summary>Réponse</summary>

`borgmatic.timer`, `OnCalendar=*-*-* 01:00:00`, avec `Persistent=true` : un
run manqué est rattrapé au démarrage suivant. À vérifier :
`ansible/roles/borgmatic/defaults/main.yml`, `templates/borgmatic.timer.j2`.
</details>

**2.** Pourquoi un sous-compte Storage Box par hôte, plutôt que le compte principal partout ?

<details><summary>Réponse</summary>

Chaque sous-compte ne voit que `backup/<hôte>` : root compromis sur un hôte ne
peut ni lire ni effacer les dépôts des autres. Et les snapshots de la Storage
Box (9 quotidiens) ne sont effaçables par aucun sous-compte. À vérifier :
`tofu/pangolin/storage_box_subaccounts.tf`, `storage_box.tf`.
</details>

**3. (QCM)** Dans la config borgmatic, où vont `keep_daily`, `keep_weekly`… ?

- a) sous `retention:`
- b) au premier niveau
- c) sous `consistency:`

<details><summary>Réponse</summary>

b. Même chose pour `checks:` (pas sous `consistency:`). Rétention : 7, 4, 6, 1.
À vérifier : `ansible/roles/borgmatic/templates/app.yaml.j2`, AGENTS.md.
</details>

**4.** Pourquoi les bases SQLite sont-elles copiées par `sqlite3 .backup` dans un hook, et pas par le hook `sqlite_databases` de borgmatic ?

<details><summary>Réponse</summary>

Le `.dump` en flux de borgmatic garde un verrou de lecture tant que borg n'a
pas fini d'envoyer, soit toute la durée de l'envoi vers la Storage Box. Une
base en mode journal ne peut plus écrire pendant ce temps : Pangolin entier a
été figé le 07/10/2026. `.backup` ne tient le verrou que le temps de la copie
locale. À vérifier : `ansible/roles/borgmatic/defaults/main.yml`
(`borgmatic_app_sqlite_databases`).
</details>

**5.** Une exclusion `cache/*` dans `borgmatic_app_exclude_patterns` exclut-elle le cache de l'appli ?

<details><summary>Réponse</summary>

Non : les motifs sont du style `fm:` de borg, ancrés au début du chemin
archivé. Un motif relatif ne correspond à rien ; il faut le chemin absolu
(`/opt/apps/<app>/cache/*`). `*.log` marche partout parce que `*` traverse les
`/`. À vérifier : `ansible/roles/borgmatic/defaults/main.yml`.
</details>

**6. (Que fais-tu si…)** Tu ajoutes un nouvel hôte sauvegardé. Dans quel ordre lancer les playbooks ?

<details><summary>Réponse</summary>

1. le playbook de l'hôte avec `--tags setup` (le rôle borgmatic génère la clé
   de root) ; 2. `ansible/backup.yaml` (crée `backup/<hôte>` et y autorise la
   clé) ; 3. le playbook complet. Lancer le playbook complet d'abord échoue au
   `repo-create`. Il faut aussi l'hôte dans `local.backup_hosts`
   (`tofu/pangolin/storage_box_subaccounts.tf`) et dans
   `backup_storage_box_hosts` (`ansible/host_vars/backups/variables.yaml`). À
   vérifier : commentaire en tête de `ansible/backup.yaml`.
</details>

**7.** Pourquoi `backup.yaml` est-il en `gather_facts: false` et n'utilise-t-il que `raw` et `scp` ?

<details><summary>Réponse</summary>

La Storage Box n'offre qu'un shell restreint : pas de Python, pas de
redirection. Les modules Ansible classiques n'y marchent pas. À vérifier :
`ansible/backup.yaml`.
</details>

**8. (Que fais-tu si…)** Un hôte compromis a effacé tous ses dépôts Borg.

<details><summary>Réponse</summary>

Les snapshots de la Storage Box (`snapshot_plan`, 9 automatiques) les gardent,
et aucun sous-compte ne peut les supprimer. Restaurer un snapshot depuis la
console Hetzner avec le compte principal, après avoir isolé l'hôte et changé sa
clé. À vérifier : `tofu/pangolin/storage_box.tf`.
</details>

## SOPS et la précédence des variables Ansible

**1.** Quels sont les deux fichiers SOPS, et qui lit chacun ?

<details><summary>Réponse</summary>

`secrets.sops.yaml` (racine) : jetons cloud et passphrase des states, lus par
mise (`_.file` dans `mise.toml`) et par les modules Tofu (`data "sops_file"`).
`ansible/secrets.sops.yaml` : secrets des applis, lus par les playbooks
(`community.sops.load_vars` dans `ansible/tasks/pangolin_config_outputs.yml`),
par la CI et par `tofu/github`. À vérifier : `.sops.yaml`, `tofu/*/secrets.tf`.
</details>

**2. (QCM)** La clé age `github-actions` de la CI peut déchiffrer :

- a) les deux fichiers
- b) `ansible/secrets.sops.yaml` seulement
- c) aucun, elle ne sert qu'à signer

<details><summary>Réponse</summary>

b. Les jetons cloud du fichier racine (Hetzner, OVH, Cloudflare, Proxmox, S3)
lui restent fermés. À vérifier : `.sops.yaml`.
</details>

**3. (QCM)** Une clé de `ansible/secrets.sops.yaml` porte le même nom qu'une variable passée dans les `vars:` d'une entrée `roles:`. Qui gagne ?

- a) les `vars:` de l'entrée `roles:`
- b) le secret SOPS
- c) le dernier défini

<details><summary>Réponse</summary>

b. `load_vars` range les secrets dans la couche `include_vars`, qui bat les
défauts de rôle, `group_vars`/`host_vars`, les `vars:` de play et d'entrée
`roles:`. Ils ne perdent que face à `set_fact`, aux paramètres d'`include_role`
et aux extra vars. D'où la règle : jamais une clé SOPS du nom d'une variable
qu'un playbook ou un rôle pose. À vérifier : AGENTS.md (« Precedence »),
`.github/scripts/check_sops_shadowing.py`.
</details>

**4.** Pourquoi les secrets de Flip Planning s'appellent-ils `prod_planning_*` et `demo_planning_*`, et pas `flip_planning_*` ?

<details><summary>Réponse</summary>

Le rôle `flip_planning` est appliqué trois fois dans `flip.yml` (prod, démo,
démo Keycloak), chaque instance surchargeant ses variables dans les `vars:` de
son entrée. Une clé SOPS `flip_planning_db_password` battrait ces `vars:` et
donnerait le même mot de passe à toutes les instances. Chaque playbook passe
donc `prod_planning_*` à la bonne instance. À vérifier : `ansible/flip.yml`,
AGENTS.md (« Running a second environment »).
</details>

**5.** Pourquoi la démo de Flip Planning a-t-elle un jour poussé ses sauvegardes sur le moniteur de la production ?

<details><summary>Réponse</summary>

`flip.yml` faisait un `set_fact` de `flip_planning_backup_healthcheck_url` au
niveau de la play. Un `set_fact` bat les `vars:` de chaque entrée `roles:` : la
démo recevait l'URL de la prod. Le playbook pose maintenant
`prod_planning_backup_healthcheck_url` et le passe à l'instance de prod. À
vérifier : AGENTS.md, pre_tasks de `ansible/flip.yml`.
</details>

**6. (Que fais-tu si…)** Tu ajoutes un destinataire age dans `.sops.yaml`.

<details><summary>Réponse</summary>

`sops updatekeys <fichier>` sur chaque fichier concerné, puis `sops rotate -i
<fichier>` pour renouveler la clé de données. À vérifier : commentaire en tête
de `.sops.yaml`.
</details>

**7. (Que fais-tu si…)** Un playbook échoue sur `return_method` de `community.sops.load_vars`.

<details><summary>Réponse</summary>

ansible-core est en dessous de 2.21. Réinstaller l'environnement épinglé :
`uv sync --locked` (le venv est dans `.venv`, mis dans le `PATH` par mise). À
vérifier : `uv.lock`, AGENTS.md.
</details>

**8.** Comment lire les sorties du state `pangolin_config` dans un playbook ?

<details><summary>Réponse</summary>

La pré-tâche commune `ansible/tasks/pangolin_config_outputs.yml` pose le fait
`terraform_outputs` (`no_log`, téléchargé une fois par run). Le playbook fait
ensuite son propre `set_fact` sous la forme littérale `<var>: "{{
terraform_outputs.<sortie>.value | default('') }}"`, forme que
`tofu/pangolin_config/tests/invariants.tftest.hcl` cherche dans les playbooks.
</details>

## Modules Tofu, states et chiffrement

**1. (QCM)** Dans quel ordre appliquer les modules après un changement qui les touche tous ?

- a) `pangolin_config`, puis `pangolin`, puis les playbooks
- b) `pangolin`, puis `pangolin_config` (et `dns`), puis les playbooks
- c) n'importe lequel

<details><summary>Réponse</summary>

b. `pangolin_config` et `dns` lisent le state de `pangolin` (IP de flip, IP
publique de Pangolin) ; les playbooks lisent celui de `pangolin_config` (URL
push, identifiants Newt). À vérifier : `README.md`, `tofu/*/remote_state.tf`.
</details>

**2.** Quels states sont chiffrés, et pourquoi pas celui de `pangolin_config` ?

<details><summary>Réponse</summary>

`pangolin`, `github` et `s3_state` (AES-GCM, clé dérivée par PBKDF2 de
`TF_VAR_state_encryption_passphrase`, sans repli en clair). `pangolin_config`
reste en clair parce qu'Ansible le lit directement sur S3 ; un utilisateur S3
dédié n'a le droit de lire que cet objet. À vérifier : `tofu/*/encryption.tf`,
`tofu/s3_state/user_ansible.tf`.
</details>

**3. (Que fais-tu si…)** Tu perds `TF_VAR_state_encryption_passphrase`.

<details><summary>Réponse</summary>

Les states chiffrés deviennent illisibles : plus de plan possible sur
`pangolin`, `github`, `s3_state`, ni sur `dns` et `pangolin_config` qui lisent
celui de `pangolin`. Il faudrait réimporter chaque ressource dans un state neuf.
Elle est dans le SOPS racine ; la garder aussi dans le gestionnaire de mots de
passe. À vérifier : `tofu/pangolin/encryption.tf`.
</details>

**4.** Qu'est-ce que le piège des attributs « optional + computed » du provider Pangolin ?

<details><summary>Réponse</summary>

Un attribut non déclaré prend la valeur que l'API renvoie, et le plan ne voit
jamais sa dérive. Un `hc_scheme` resté NULL a coupé deux sites pendant des
heures. Réponse du dépôt : tout attribut de ce type est déclaré en littéral
(`local.resource_pins`, `resource_defaults.tf` ; sondes dans `websites.tf`) et
un audit au plan échoue sur une sonde sans schéma ni port. À vérifier :
`tofu/pangolin_config/resource_defaults.tf`, `maintenance.tf`, `rules.tf`.
</details>

**5.** Pourquoi `tofu/1y` et `tofu/site` ont-ils un `tests/.disabled` ?

<details><summary>Réponse</summary>

Leurs blocs `import` font paniquer `tofu test` (OpenTofu refuse les imports en
contexte de test). Les tests reviendront une fois le bloc retiré ; préférer la
commande `tofu import` documentée dans le README du module. À vérifier :
`tofu/1y/tests/.disabled`, AGENTS.md (« Tests »).
</details>

**6. (QCM)** Quelles ressources portent `prevent_destroy` dans `tofu/pangolin` ?

- a) aucune
- b) le serveur Pangolin, le serveur flip et la Storage Box
- c) seulement la Storage Box

<details><summary>Réponse</summary>

b. Pangolin (la porte d'entrée), flip (bases de prod et de démo), la Storage
Box (toutes les sauvegardes). À vérifier : `tofu/pangolin/pangolin.tf`,
`flip.tf`, `storage_box.tf`.
</details>

**7.** Tu viens de créer un hôte dans `tofu/pangolin`. Pourquoi Ansible ne le voit-il pas encore ?

<details><summary>Réponse</summary>

L'inventaire est dynamique : `ansible/inventory/hetzner.py` et `proxmox.py`
lancent `tofu show -json` dans `tofu/pangolin` et `tofu/proxmox`. Tant que
l'apply n'est pas fait, l'hôte n'est pas dans le state. Il lui faut aussi sa
clé dans `ansible/known_hosts`.
</details>

**8.** Comment tester un module Tofu sans toucher à l'infra ?

<details><summary>Réponse</summary>

`mise run tofu-test` (depuis la racine) : `tofu init -backend=false` puis
`tofu test` pour chaque `tofu/<module>/tests/`, tous les providers en
`mock_provider`, les data sources `sops_file` / `terraform_remote_state` en
`override_data`. À vérifier : `mise.toml`, AGENTS.md.
</details>

## La CI et son ruleset

**1.** Qu'est-ce qui déclenche un déploiement sur les vrais hôtes ?

<details><summary>Réponse</summary>

Un push sur `main` qui touche `ansible/roles/**` ou l'un des playbooks
`docker.yml`, `pi.yml`, `pangolin.yaml`, `flip.yml` ; ou un lancement manuel
(`workflow_dispatch`, avec `playbook` et `tags`). Merger une PR, c'est
déployer. À vérifier : `.github/workflows/deploy-docker-app.yaml`.
</details>

**2. (QCM)** Tu modifies seulement `ansible/docker.yml` (pas de rôle). Que déploie le merge ?

- a) tout `docker.yml`
- b) rien : seuls les chemins `ansible/roles/<rôle>/` sont traduits en tags
- c) les rôles tagués `app`

<details><summary>Réponse</summary>

b. Le workflow démarre, mais `resolve_docker_tags.py` ne trouve aucun rôle
modifié et s'arrête sur « No matching role changed ». Un changement de
`host_vars` ou de `group_vars` ne déclenche même pas le workflow. Il faut alors
le lancer à la main avec les tags voulus. À vérifier :
`.github/scripts/resolve_docker_tags.py`.
</details>

**3.** Une PR modifie le rôle `borgmatic`. Qu'est-ce qui part en production au merge ?

<details><summary>Réponse</summary>

Le rôle porte `tags: backup,setup` dans les quatre playbooks d'hôte ; `setup`
est générique, il reste `backup`. Le merge lance donc `--tags backup` sur
docker, pi, pangolin **et** flip : le rôle borgmatic et la partie sauvegarde de
chaque appli, sur tous les hôtes à la fois. À vérifier :
`resolve_docker_tags.py` (`GENERIC_TAGS`), les playbooks.
</details>

**4.** Quels checks le ruleset de `main` exige-t-il, et qui peut le contourner ?

<details><summary>Réponse</summary>

Une PR (sans relecteur obligatoire) et les checks `Ansible lint`, `OpenTofu
lint`, `Tests` et `CI lint`, sans exiger une branche à jour. Ni force-push ni
suppression. Le rôle admin (le propriétaire) peut contourner pour un correctif
urgent. À vérifier : `tofu/github/ruleset_homelab.tf`.
</details>

**5.** Pourquoi une branche de PR ne peut-elle pas lire la clé age de la CI ?

<details><summary>Réponse</summary>

Les secrets de déploiement (`SOPS_AGE_KEY`, `SSH_PRIVATE_KEY`, `OLM_*`) sont
dans l'environnement GitHub `production`, dont la politique n'autorise que la
branche `main`. Même un collaborateur ou une action compromise sur une branche
ne les voit pas. À vérifier : `tofu/github/environments.tf`.
</details>

**6.** Comment la CI joint-elle la VM docker, qui est à la maison sans port ouvert ?

<details><summary>Réponse</summary>

Elle lance un conteneur `fosrl/olm` (client Pangolin) sur le runner, pointe le
DNS du runner sur le proxy DNS d'OLM (`100.96.128.1`) et atteint
`docker-apps.internal` et `pi.internal`, ressources privées servies par le Newt
du LXC Proxmox. Pangolin est joint directement par son nom public, flip par son
IP privée avec `ProxyJump=pangolin.sylvain.cloud`. Les runs sont sérialisés :
OLM refuse deux connexions avec les mêmes identifiants. À vérifier :
`deploy-docker-app.yaml`, `ping.yaml`.
</details>

**7. (Que fais-tu si…)** Une PR Renovate mergée a cassé une appli.

<details><summary>Réponse</summary>

Un revert par PR (`git revert <sha>`), dont le merge redéploie l'ancien digest.
Si la nouvelle version a migré des données (schéma de base), le revert ne
suffit pas : restaurer aussi la sauvegarde d'avant. Voir
`docs/runbooks/deploiement-ci-casse.md`.
</details>

**8. (QCM)** Quelles mises à jour Renovate fusionnent toutes seules ?

- a) toutes les mineures et correctifs
- b) les versions mineures et correctifs de `planning-equipes`, les digests de `main` de `planning-equipes` (démo) et de `promptoramix`
- c) aucune

<details><summary>Réponse</summary>

b. Le reste attend un merge manuel ; les montées majeures des images avec
données (PostgreSQL, MariaDB, Redis/Valkey, Meilisearch) n'ouvrent même pas de
PR avant qu'on coche leur case sur le Dependency Dashboard. À vérifier :
`renovate.json`.
</details>
