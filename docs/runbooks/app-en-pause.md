# Mettre une appli en pause, la reprendre

Une appli qu'on n'utilise plus pour l'instant, sans vouloir la supprimer
(pour la supprimer : skill `remove-app`). En pause, rien n'est détruit :
compose, données, volumes, dépôt borg et ses archives, ressource Pangolin,
jetons et moniteurs restent ; plus rien ne tourne ni n'alerte. Seul
Paperless-ngx a l'interrupteur aujourd'hui (en pause depuis octobre 2026).

## Les quatre endroits

| Où | Pause | Effet |
|---|---|---|
| `ansible/host_vars/docker/variables.yaml` | `paperless_enabled: false` | `dc@paperless` arrêtée et désactivée, aucun handler de redémarrage ; `/etc/borgmatic.d/paperless.yaml` retiré. Le compose reste templaté |
| `tofu/pangolin_config/website_paperless.tf` | `enabled = false` dans l'entrée | ressource Pangolin désactivée, moniteurs « Healthcheck » et « Backup » en pause (`websites.tf`) |
| `tofu/pangolin_config/tests/invariants.tftest.hcl` | `["paperless"]` dans la liste des apps en pause | la liste est écrite en toutes lettres : une pause est une décision |
| `.github/restore-test/apps.json` | `"paused": true` | le test de restauration du 1er et du 15 saute l'app ; un run manuel qui la nomme restaure sa dernière archive sans en exiger l'âge |

Le `tofu test` de `pangolin_config` exige que `"paused"` d'`apps.json`
marque exactement les apps dont le moniteur « Backup » est en pause.

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
   rejoue le rôle (`--tags paperless`) : unité arrêtée, configuration
   borgmatic retirée. Sinon, à la main :
   `ansible-playbook docker.yml --tags paperless --check --diff`, puis sans
   `--check`.
3. `mise run plan` puis `mise run apply` dans `tofu/pangolin_config` :
   ressource désactivée, deux moniteurs en pause (3 changements en place,
   aucune destruction). Avant ou après le merge, peu importe ; après, la
   nuit suivante ne laisse aucun moniteur rouge.

Le `check "target_health"` du plan signale la cible de Paperless en échec
tant que la ressource est encore active ; une fois désactivée, il l'ignore
(`rules.tf`).

## Reprendre

1. PR inverse : `paperless_enabled: true` (ou la ligne retirée, c'est le
   défaut), `enabled = false` retiré de `website_paperless.tf`, la liste des
   apps en pause vidée dans `invariants.tftest.hcl`, `"paused": true` retiré
   d'`apps.json`.
2. `mise run apply` dans `tofu/pangolin_config` **avant** le merge :
   ressource réactivée et moniteurs repris. L'URL de push n'a pas changé.
3. Merge : le déploiement redémarre `dc@paperless` et repose la
   configuration borgmatic (`repo-create` trouve le dépôt existant et passe).
4. Vérifier : `systemctl --user status dc@paperless`, la page
   `papiers.sylvain.cloud`, puis le moniteur « Backup Paperless-ngx » le
   lendemain. Le test de restauration suivant exige une archive de moins de
   28 h : ne pas reprendre la veille d'un 1er ou d'un 15 sans lancer
   `sudo /root/.local/bin/borgmatic --config /etc/borgmatic.d/paperless.yaml create` à la main.

## Une autre appli

Le même interrupteur se pose dans son rôle, sur le modèle de
`roles/paperless_ngx` : `<app>_enabled` en défaut, état de l'unité qui en
dépend, configuration borgmatic retirée (`file: state=absent`) quand il est
faux, handler `when: <app>_enabled`, et un `side_effect.yml` Molecule qui
passe par les deux états.
