# Mettre une appli en pause, la reprendre

Une appli qu'on n'utilise plus pour l'instant, sans vouloir la supprimer
(pour la supprimer : skill `remove-app`). En pause, rien n'est détruit :
compose, données, volumes, dépôt borg et ses archives, ressource Pangolin,
jetons et moniteurs restent ; plus rien ne tourne ni n'alerte. Deux apps
sont en pause, depuis octobre 2026 : Paperless-ngx et le banc Keycloak de
Flip Planning (`demo_planning_kc`, voir [plus bas](#le-banc-keycloak-de-flip-planning)).

## Les quatre endroits

| Où | Pause | Effet |
|---|---|---|
| `ansible/host_vars/docker/variables.yaml` | `paperless_enabled: false` | `dc@paperless` arrêtée et désactivée, aucun handler de redémarrage ; `/etc/borgmatic.d/paperless.yaml` retiré. Le compose reste templaté |
| `tofu/pangolin_config/website_paperless.tf` | `enabled = false` dans l'entrée | ressource Pangolin désactivée, moniteurs « Healthcheck » et « Backup » en pause, sonde Pangolin de ses cibles coupée (`hc_enabled`, `websites.tf`) |
| `tofu/pangolin_config/tests/invariants.tftest.hcl` | `"paperless"` dans la liste des apps en pause (`["demo_planning_kc", "paperless"]` aujourd'hui) | la liste est écrite en toutes lettres : une pause est une décision |
| `.github/restore-test/apps.json` | `"paused": true` | le test de restauration du 1er et du 15 saute l'app ; un run manuel qui la nomme restaure sa dernière archive sans en exiger l'âge |

Hors de ces quatre endroits, `renovate.json` porte une règle « Paused apps »
(`enabled: false` sur `ansible/roles/paperless_ngx/**`, plus une seconde
sur l'image Paperless de `path_bypass_images.json`, que Renovate monterait
sinon seule, PR que le test `path_bypasses_follow_their_image` refuse) :
aucune PR de mise à jour pour une appli qui ne tourne pas. La reprise retire les règles dans la
même PR ; Renovate propose alors les versions parues entre-temps. Le banc
Keycloak n'en a pas besoin : ses images sont écrites dans `flip.yml` sur le
tag mobile `pr-72`, qu'aucun manager ne lit.

Le `tofu test` de `pangolin_config` exige que `"paused"` d'`apps.json`
marque exactement les apps dont le moniteur « Backup » est en pause, et que
`paperless_enabled` (`host_vars/docker`) soit égal à `enabled` de l'entrée.

## Pourquoi la configuration borgmatic part

Le dump PostgreSQL passe par `docker exec` dans le conteneur de la base :
arrêté, il échoue chaque nuit et met `borgmatic.service` en échec. Sans
configuration, borgmatic ne touche plus du tout au dépôt : ni `create`, ni
`prune`, ni `check`. Le dépôt `backup/docker/paperless` et ses archives
restent tels quels sur la Storage Box.

Même si `prune` tournait, l'historique ne fondrait pas : `keep_daily: 7`
garde la dernière archive de chacun des 7 derniers jours **qui ont une
archive**, pas des 7 derniers jours du calendrier (idem pour
`keep_weekly`/`monthly`/`yearly`). Un dépôt qui ne reçoit plus rien garde
indéfiniment ses archives.

## Mettre en pause

1. Arrêter l'appli sur l'hôte si on n'attend pas le déploiement :
   `systemctl --user disable --now dc@paperless` (VM docker).
2. PR avec les quatre changements ci-dessus. Au merge, `deploy-docker-app`
   ne rejoue le rôle (`--tags paperless`) que si la PR touche aussi
   `ansible/roles/**` : un changement de `host_vars` seul ne déclenche aucun
   déploiement (filtre `paths` du workflow, `resolve_docker_tags.py` ne lit
   que les rôles). Sinon, après le merge, à la main :
   `ansible-playbook docker.yml --tags paperless --check --diff`, puis sans
   `--check` (ou `workflow_dispatch` de `deploy-docker-app`, playbook
   `docker`, tags `paperless`) : unité arrêtée, configuration borgmatic
   retirée.
3. `tofu plan` puis `tofu apply` dans `tofu/pangolin_config` (pas
   `mise run plan`/`apply`, qui visent `tofu/pangolin`) :
   ressource désactivée, deux moniteurs en pause, sonde de la cible coupée
   (4 changements en place, aucune destruction). Avant ou après le merge, peu importe ; après, la
   nuit suivante ne laisse aucun moniteur rouge.

Le `check "target_health"` du plan signale la cible de Paperless en échec
tant que la ressource est encore active ; une fois désactivée, il l'ignore
(`rules.tf`), et Newt ne la sonde plus du tout.

## Reprendre

1. PR inverse : `paperless_enabled: true` (ou la ligne retirée, c'est le
   défaut), `enabled = false` retiré de `website_paperless.tf`, la liste des
   apps en pause vidée dans `invariants.tftest.hcl`, `"paused": true` retiré
   d'`apps.json`, et les deux règles « Paused apps » de `renovate.json`
   retirées (ou `paperless_ngx` et son image retirés de leurs listes).
2. `tofu apply` dans `tofu/pangolin_config` **avant** le merge :
   ressource réactivée, moniteurs repris, sonde de la cible rallumée. L'URL
   de push n'a pas changé.
3. Merge, puis `ansible-playbook docker.yml --tags paperless` (ou
   `workflow_dispatch` de `deploy-docker-app`, tags `paperless`) : une PR qui
   ne touche que `host_vars` ne déclenche aucun déploiement. Le rôle
   redémarre `dc@paperless` et repose la configuration borgmatic
   (`repo-create` trouve le dépôt existant et passe).
4. Vérifier : `systemctl --user status dc@paperless`, la page
   `papiers.sylvain.cloud`, puis le moniteur « Backup Paperless-ngx » le
   lendemain. Le test de restauration suivant exige une archive de moins de
   28 h : ne pas reprendre la veille d'un 1er ou d'un 15 sans lancer
   `sudo /root/.local/bin/borgmatic --config /etc/borgmatic.d/paperless.yaml create` à la main.

## Le banc Keycloak de Flip Planning

`demo-planning-kc.sylvain.dev` est la troisième application du rôle
`flip_planning` dans `ansible/flip.yml` : l'interrupteur n'est pas dans
`host_vars/flip` (il mettrait en pause la production et la démo avec), mais
dans les `vars:` de son entrée, `flip_planning_enabled: false` (jamais un
`set_fact` ni une clé SOPS de ce nom, qui battraient les `vars:` de chaque
instance). Les mêmes quatre endroits, adaptés :

| Où | Pause | Effet |
|---|---|---|
| `ansible/flip.yml`, entrée `demo_planning_kc` | `flip_planning_enabled: false` | `dc@demo_planning_kc` arrêtée et désactivée, aucune notification de redémarrage, configuration borgmatic retirée (il n'en a pas : `flip_planning_backup_enabled: false`). Compose, `.env`, volumes gardés |
| `tofu/pangolin_config/website_demo_planning_kc.tf` | `enabled = false` dans l'entrée | ressource Pangolin désactivée, sonde Pangolin de ses trois cibles coupée (`hc_enabled`), lien retiré de la sortie `homepage_links` (Homepage le perd au prochain `docker.yml --tags homepage`) ; ni healthcheck ni moniteur « Backup » à mettre en pause, il n'en a pas |
| `tofu/pangolin_config/tests/invariants.tftest.hcl` | `"demo_planning_kc"` dans la liste des apps en pause | et `flip_planning_enabled` de l'entrée de `flip.yml` doit être égal à `enabled` |
| `.github/restore-test/apps.json` | rien | pas d'entrée : le banc n'est pas sauvegardé |

Le rôle s'applique trois fois dans le même play : un `when` sur le handler
« Restart demo_planning_kc » lirait les paramètres de la dernière application
du rôle, pas forcément les siens. Les tâches notifient donc
`flip_planning_restart_handlers`, vide quand l'instance est en pause.

Au merge, `deploy-docker-app` rejoue le rôle (`ansible/roles/**` et
`flip.yml` changent) : unité désactivée, la production et la démo ne
redémarrent que si leur compose a changé. `tofu apply` dans
`tofu/pangolin_config` : la ressource et la sonde de ses trois cibles
changent, en place. Pour
reprendre : `flip_planning_enabled: false` retiré de `flip.yml`,
`enabled = false` retiré de l'entrée, la liste des apps en pause mise à jour,
et le scénario Molecule `flip_planning` dans la même PR : la copie de
l'entrée dans `converge.yml`, `side_effect.yml` (il part d'un banc en pause et
le vérifie) et `verify.yml` (`assert_kc_paused.yml`,
`verify_app_unit_started: false`) supposent la pause et font échouer les tests
sinon ; puis `tofu apply` et merge (le rôle redémarre l'unité). Le banc suit le tag
mobile `pr-72` (`pull_policy: always`) : à la reprise, l'image doit encore
exister sur ghcr.io.

## Une autre appli

Le même interrupteur se pose dans son rôle, sur le modèle de
`roles/paperless_ngx` : `<app>_enabled` en défaut, état de l'unité qui en
dépend, configuration borgmatic retirée (`file: state=absent`) quand il est
faux, handler `when: <app>_enabled`, et un `side_effect.yml` Molecule qui
passe par les deux états. Pour un rôle appliqué plusieurs fois, le modèle est
`roles/flip_planning` (paramètre de rôle, notification retenue).
