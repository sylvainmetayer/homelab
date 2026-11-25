# Mettre une appli en pause, la reprendre

Une appli qu'on n'utilise plus pour l'instant, sans vouloir la supprimer
(pour la supprimer : skill `remove-app`). En pause, rien n'est détruit :
compose, données, volumes, dépôt borg et ses archives, ressource Pangolin,
jetons et moniteurs restent ; plus rien ne tourne ni n'alerte. Une seule app
est en pause : la démo de Flip Planning (`demo_planning_enabled: false` dans
`host_vars/flip`, lu par son entrée de `flip.yml`, depuis le 2026-11-11 : sa
mémoire avait été libérée pour l'essai de Postiz, retiré depuis ; laissée en
pause). Le banc Keycloak et la vitrine publique de Flip Planning l'ont été
jusqu'à leur retrait (novembre 2026). Paperless-ngx a été en pause d'octobre à novembre 2026, puis
supprimé (remplacé par Papra) : les exemples ci-dessous disent `<app>` et
supposent la voie `host_vars` (Paperless, Postiz le 2026-11-11, retiré depuis ; la démo de Flip
Planning la suit par une variable propre, `demo_planning_enabled`, que son
entrée de `flip.yml` passe à `flip_planning_enabled`).

## Les quatre endroits

| Où | Pause | Effet |
|---|---|---|
| `ansible/host_vars/docker/variables.yaml` | `<app>_enabled: false` | `dc@<app>` arrêtée et désactivée, aucun handler de redémarrage ; `/etc/borgmatic.d/<app>.yaml` retiré. Le compose reste templaté |
| `tofu/pangolin_config/website_<app>.tf` | `enabled = false` dans l'entrée | ressource Pangolin désactivée, moniteurs « Healthcheck » et « Backup » en pause, sonde Pangolin de ses cibles coupée (`hc_enabled`, `websites.tf`) |
| `tofu/pangolin_config/tests/invariants.tftest.hcl` | `"<app>"` dans la liste des apps en pause (`["demo_planning"]` aujourd'hui) | la liste est écrite en toutes lettres : une pause est une décision |
| `.github/restore-test/apps.json` | `"paused": true` | le test de restauration du 1er et du 15 saute l'app ; un run manuel qui la nomme restaure sa dernière archive sans en exiger l'âge |

Hors de ces quatre endroits, `renovate.json` porte une règle « Paused apps »
(`enabled: false` sur `ansible/roles/<app>/**`, plus une seconde
sur l'image de l'app dans `path_bypass_images.json` si elle y figure, que
Renovate monterait sinon seule, PR que le test
`path_bypasses_follow_their_image` refuse ; aucune n'existe aujourd'hui) :
aucune PR de mise à jour pour une appli qui ne tourne pas. La reprise retire les règles dans la
même PR ; Renovate propose alors les versions parues entre-temps. Le banc
Keycloak n'en a pas besoin : ses images sont écrites dans `flip.yml` sur le
tag mobile `pr-72`, qu'aucun manager ne lit.

Le `tofu test` de `pangolin_config` exige que `"paused"` d'`apps.json`
marque exactement les apps dont le moniteur « Backup » est en pause, et que
`<app>_enabled` (`host_vars/docker`) soit égal à `enabled` de l'entrée.

## Pourquoi la configuration borgmatic part

Le dump PostgreSQL passe par `docker exec` dans le conteneur de la base :
arrêté, il échoue chaque nuit et met `borgmatic.service` en échec. Sans
configuration, borgmatic ne touche plus du tout au dépôt : ni `create`, ni
`prune`, ni `check`. Le dépôt `backup/docker/<app>` et ses archives
restent tels quels sur la Storage Box.

Même si `prune` tournait, l'historique ne fondrait pas : `keep_daily: 7`
garde la dernière archive de chacun des 7 derniers jours **qui ont une
archive**, pas des 7 derniers jours du calendrier (idem pour
`keep_weekly`/`monthly`/`yearly`). Un dépôt qui ne reçoit plus rien garde
indéfiniment ses archives.

## Mettre en pause

1. Arrêter l'appli sur l'hôte si on n'attend pas le déploiement :
   `systemctl --user disable --now dc@<app>` (VM docker).
2. PR avec les quatre changements ci-dessus. Au merge, `deploy-docker-app`
   rejoue `docker.yml` en entier (`--tags all`) : un changement de
   `host_vars/docker` redéploie tout le playbook de l'hôte
   (`resolve_docker_tags.py`). Unité arrêtée, configuration borgmatic
   retirée. Pour le vérifier avant le merge :
   `ansible-playbook docker.yml --tags <app> --check --diff`.
3. `mise run tofu pangolin_config plan` puis `apply` (pas
   `mise run plan-pangolin`/`apply-pangolin`, qui visent `tofu/pangolin`) :
   ressource désactivée, deux moniteurs en pause, sonde de la cible coupée
   (4 changements en place, aucune destruction). Avant ou après le merge, peu importe ; après, la
   nuit suivante ne laisse aucun moniteur rouge.

Le `check "target_health"` du plan signale la cible de l'app en échec
tant que la ressource est encore active ; une fois désactivée, il l'ignore
(`rules.tf`), et Newt ne la sonde plus du tout.

## Reprendre

1. PR inverse : `<app>_enabled: true` (ou la ligne retirée, c'est le
   défaut), `enabled = false` retiré de `website_<app>.tf`, la liste des
   apps en pause vidée dans `invariants.tftest.hcl`, `"paused": true` retiré
   d'`apps.json`, et les deux règles « Paused apps » de `renovate.json`
   retirées (ou `<app>` et son image retirés de leurs listes).
2. `tofu apply` dans `tofu/pangolin_config` **avant** le merge :
   ressource réactivée, moniteurs repris, sonde de la cible rallumée. L'URL
   de push n'a pas changé.
3. Merge : `deploy-docker-app` rejoue `docker.yml` en entier (changement
   de `host_vars/docker`). Le rôle redémarre `dc@<app>` et repose la
   configuration borgmatic (`repo-create` trouve le dépôt existant et
   passe).
4. Vérifier : `systemctl --user status dc@<app>`, la page
   de l'app, puis son moniteur « Backup » le
   lendemain. Le test de restauration suivant exige une archive de moins de
   28 h : ne pas reprendre la veille d'un 1er ou d'un 15 sans lancer
   `sudo /root/.local/bin/borgmatic --config /etc/borgmatic.d/<app>.yaml create` à la main.

## Une autre appli

Le même interrupteur se pose dans son rôle, sur le modèle de
`roles/flip_planning` (ou, pour un rôle appliqué une fois, du Paperless-ngx d'avant sa suppression, dans l'historique git) : `<app>_enabled` en défaut, état de l'unité qui en
dépend, configuration borgmatic retirée (`file: state=absent`) quand il est
faux, handler `when: <app>_enabled`, et un `side_effect.yml` Molecule qui
passe par les deux états. Pour un rôle appliqué plusieurs fois, le modèle est
`roles/flip_planning` (paramètre de rôle, notification retenue).
