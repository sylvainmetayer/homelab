# Déploiement CI cassé, ou PR Renovate qui casse une appli

Rappels :

- `deploy-docker-app.yaml` part à chaque **push sur `main`** qui touche
  `ansible/roles/**` ou un playbook d'hôte (`docker.yml`, `pi.yml`,
  `pangolin.yaml`, `flip.yml`). Il déduit les tags des rôles modifiés
  (`.github/scripts/resolve_docker_tags.py`), ouvre le tunnel OLM vers
  Pangolin, puis lance les playbooks concernés.
- Il tourne dans l'environnement GitHub `production` : ses secrets
  (`SOPS_AGE_KEY`, `SSH_PRIVATE_KEY`, `OLM_ID`, `OLM_SECRET`,
  `PANGOLIN_ENDPOINT`) ne sont lisibles que depuis `main`
  (`tofu/github/environments.tf`).
- Le ruleset de `main` (`tofu/github/ruleset_homelab.tf`) exige une PR et les
  checks `Ansible lint`, `OpenTofu lint`, `Tests`, `CI lint`. Le rôle admin
  peut contourner.
- Les runs sont sérialisés (`concurrency: deploy-docker-app`) : le VPN OLM
  refuse deux connexions avec les mêmes identifiants. GitHub ne garde qu'**un**
  run en attente par groupe : plusieurs merges à la suite annulent les runs
  intermédiaires (« cancelled »). Ce n'est pas une perte : chaque run déploie
  tout ce qui a changé depuis le dernier run de push **réussi**, donc le
  suivant rattrape un run annulé ou rouge (et rejoue ce qui était passé, sans
  effet puisque les rôles sont idempotents). Un hôte en échec n'empêche pas de
  déployer les suivants : tant qu'il reste en panne, chaque run le retente et
  reste rouge.

## Symptôme

- Run `Deploy changed docker app` rouge dans l'onglet Actions.
- Ou run vert, mais une appli DOWN juste après le merge d'une PR (souvent
  Renovate).

## Diagnostic

```bash
gh run list --workflow deploy-docker-app.yaml --limit 5
gh run view <id> --log-failed
```

Où ça casse :

| Étape | Cause probable |
|---|---|
| `Wait OLM startup` | Pangolin injoignable, identifiants OLM invalides ([pangolin-injoignable.md](pangolin-injoignable.md)) ; tester avec `ping.yaml` (lancement manuel) |
| `Deploy …` : `Host key verification failed` | clé d'hôte changée ([cle-hote-ssh-changee.md](cle-hote-ssh-changee.md)) |
| `Deploy …` : `Permission denied (publickey)` | `keys/github-actions.pub` absente d'`authorized_keys` de l'hôte |
| `Load secrets …` | `SOPS_AGE_KEY` ne déchiffre plus (`.sops.yaml` ou destinataire `github-actions` modifié) |
| `Read Terraform state from S3 bucket` | clés `state_s3_*` invalides, bucket OVH indisponible |
| tâche d'un rôle, handler `Restart <service>` | l'appli elle-même ne démarre plus : [appli-en-panne.md](appli-en-panne.md) |
| `No matching role changed` (vert) | seul un playbook a changé, pas un rôle : rien n'est déployé |
| `Determine changed files` (vert) : « already deployed by a later successful run » | relance d'un vieux run : un run plus récent a déjà déployé ce commit, rien n'est rejoué (ce serait un retour en arrière) |
| `Determine changed files` : avertissement « no usable last successful push run » | premier run, plus aucun run réussi dans l'API ou historique réécrit : seul ce push est déployé, les runs annulés ou rouges d'avant ne sont pas rattrapés (les relancer à la main, `workflow_dispatch` avec `tags`) |

Reproduire en local, sans rien changer :

```bash
cd ansible
ansible-playbook docker.yml --tags <tag> --check --diff
```

## Réparation

- **Revenir en arrière** sur une PR qui casse : un revert, par une PR, comme
  le reste. Le merge du revert redéploie l'ancien état ; l'ancienne image est
  souvent encore là, `dc@` ne la retélécharge pas.

  ```bash
  git switch main && git pull
  git switch -c revert/<sujet>
  git revert <sha du merge>
  git push -u origin revert/<sujet>
  gh pr create --fill
  ```

  Attention aux montées qui migrent des données (base, appli qui modifie son
  schéma au démarrage) : revenir à l'ancienne image ne défait pas la
  migration. Il faut alors restaurer les données
  ([sauvegarde-et-restauration.md](sauvegarde-et-restauration.md)) en même
  temps.
- **Urgence** : l'admin peut pousser directement sur `main` (contournement du
  ruleset) ; le push déclenche le même déploiement. À réserver aux cas où
  attendre la CI coûte plus que le risque.
- **Relancer un déploiement** sans nouveau commit :

  ```bash
  gh workflow run deploy-docker-app.yaml -f playbook=docker -f tags=rss
  ```

  (`playbook` : `all`, `docker`, `pi`, `pangolin` ou `flip`.)
- **Déployer depuis le poste** (CI en panne) :
  `ansible-playbook docker.yml --tags rss`, après un `--check --diff`.
- **Secrets de la CI à refaire** (clé age, clé SSH de déploiement,
  identifiants OLM) : ils viennent de `tofu/github` (`actions_secrets.tf`,
  `ssh_key.tf`, `olm_secrets.tf`) ; `tofu plan` puis `tofu apply` dans
  `tofu/github`. Une nouvelle clé SSH réécrit `keys/github-actions.pub` : la
  committer puis rejouer `00-setup.yaml` sur les hôtes.

## Vérification

- Le run suivant est vert, et son journal montre les tags attendus
  (`Resolved: …`).
- L'appli répond, son moniteur Uptime Kuma est UP.

## Prévention

- Avant de merger une PR qui touche un rôle : savoir **ce que le merge va
  déployer**, et sur quel hôte (un changement du rôle `borgmatic` ou
  `security` part sur plusieurs hôtes à la fois).
- Lire les notes de version d'une PR Renovate d'appli. Fusionnent seules
  (`renovate.json`) : les versions de `planning-equipes` (mineures et
  correctifs) et de `promptoramix`, et la PR du lundi « weekly stateless
  automerged updates » (digests et correctifs des images sans base de la liste
  blanche, et des GitHub Actions), dès que le ruleset a ses checks verts. Un
  déploiement rouge juste après un merge de `renovate[bot]` vient donc
  souvent d'elle : revenir au digest précédent par une PR (`git revert` du
  commit), et retirer l'image de la liste blanche si elle a cassé sans que
  Molecule le voie. Les montées majeures de bases
  attendent une case cochée sur le Dependency Dashboard (la MariaDB officielle
  de Nextcloud n'en voit aucune : elle reste sur la LTS 12.3, et son Redis
  `-bookworm` sur la 8.2).
- Une PR qui touche `path_bypass_images.json` attend une approbation
  (`relecture-chemins-publics`) : relire les chemins publics listés avant
  d'approuver.

## Tests de nuit rouges

Sur une PR, `test.yaml` ne lance que les scénarios Molecule et les modules
Tofu qu'atteignent les fichiers modifiés (`.github/scripts/select_tests.py`,
le résumé du job `Discover test suites` dit pourquoi). La matrice complète
tourne chaque nuit à 03:30 UTC sur `main` : elle rattrape ce que la sélection
aurait manqué (une dépendance qu'elle ne sait pas lire) et ce qui casse sans
commit (image ou collection Galaxy republiée, registre).

- **Le voir** : GitHub notifie l'échec d'un workflow planifié à celui qui a
  modifié le `cron` en dernier (le merge de la PR qui l'a posé), par e-mail
  et sur le web selon les réglages *Notifications → Actions* (« Only
  notify for failed workflows » par défaut). Le commit de tête de `main`
  porte aussi la croix rouge du run. Sur un dépôt public, GitHub désactive
  les workflows planifiés après 60 jours sans activité : un bandeau
  l'annonce dans l'onglet Actions, `gh workflow enable test.yaml` les relance.
- **Lister** : `gh run list --workflow test.yaml --event schedule --limit 5`,
  puis `gh run view <id> --log-failed`.
- **Une suite rouge la nuit mais verte sur sa PR** : la sélection l'a sautée.
  Corriger la suite, puis apprendre la dépendance manquée à
  `select_tests.py` (et un cas à `test_select_tests.py`).
- **Matrice complète sur une PR** : poser le label `full-tests`, ou
  `gh workflow run test.yaml --ref <branche>`.
