# Déploiement CI cassé, ou PR Renovate qui casse une appli

Rappels :

- `deploy-docker-app.yaml` part à chaque **push sur `main`** qui touche
  `ansible/roles/**`, un playbook d'hôte (`docker.yml`, `pi.yml`,
  `pangolin.yaml`, `flip.yml`), `ansible/host_vars/` de ces hôtes,
  `ansible/group_vars/all/**`, `ansible/tasks/**`, `ansible/requirements.yml`,
  ou les sources du site de docs (`docs/**`, `mkdocs.yml`,
  `.github/scripts/mkdocs_*.py`). Il déduit les tags des fichiers modifiés
  (`.github/scripts/resolve_docker_tags.py`), ouvre le tunnel OLM vers
  Pangolin, puis lance les playbooks concernés.
- Il tourne dans l'environnement GitHub `production` : ses secrets
  (`SOPS_AGE_KEY`, `SSH_PRIVATE_KEY`, `OLM_ID`, `OLM_SECRET`) ne sont lisibles
  que depuis `main` (`tofu/github/environments.tf`). Deux autres sont des
  secrets du dépôt, hors de ce fichier : `PANGOLIN_ENDPOINT`, qu'aucun module
  Tofu ne gère, et `HOMELAB_SECRETS_SSH_KEY`
  (`tofu/github/repository_homelab_secrets.tf`).
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
| `Start the OLM tunnel` (action `.github/actions/olm-tunnel`, sous-étape `Wait OLM startup`) | Pangolin injoignable, identifiants OLM invalides ([pangolin-injoignable.md](pangolin-injoignable.md)) ; relancer le job (`gh run rerun <id> --failed`) une fois Pangolin revenu, l'étape `Start the OLM tunnel` montre les 5 dernières lignes du journal du conteneur `olm` à chaque essai (un conteneur sorti n'a plus de journal : `--rm`) |
| `Deploy …` : `Host key verification failed` | clé d'hôte changée ([cle-hote-ssh-changee.md](cle-hote-ssh-changee.md)) |
| `Deploy …` : `Permission denied (publickey)` | `keys/github-actions.pub` absente d'`authorized_keys` de l'hôte |
| `Load secrets …` | `SOPS_AGE_KEY` ne déchiffre plus (`.sops.yaml` ou destinataire `github-actions` modifié) |
| `Read Terraform state from S3 bucket` | clés `state_s3_*` invalides, bucket OVH indisponible |
| tâche d'un rôle, handler `Restart <service>` | l'appli elle-même ne démarre plus : [appli-en-panne.md](appli-en-panne.md) |
| `No matching role changed` (vert) | rien à déployer : seuls les commentaires ou la mise en forme d'un playbook ont changé, une entrée de rôle a été retirée, ou seul le `README.md` d'un rôle a changé (jamais lu par Ansible). Aussi un rôle absent des quatre playbooks de la CI : `nas.yml`, `pve.yml` ou `lxc.yml` (`jellyfin`, `mediamanager`…) s'appliquent **à la main**, le run vert ne les a pas déployés (avis `deployed by hand only` dans `Resolve ansible tags`) |
| `Determine changed files` (vert) : « already deployed by a later successful run » | relance d'un vieux run : un run plus récent a déjà déployé ce commit, rien n'est rejoué (ce serait un retour en arrière) |
| Run `cancelled` après le job `window` | fenêtre de calme (19:00-08:00 Paris, [ADR 0029](../adr/0029-fenetre-de-calme-du-deploiement.md)) : normal, le premier run de la fenêtre suivante (`schedule` 08:00, ou un push) déploie tout depuis le dernier succès. Urgent : `workflow_dispatch`, toujours immédiat. Rien le matin : le `schedule` a pu être retardé ou sauté par GitHub, lancer un `workflow_dispatch` sans `tags` ne rattrape pas (il ne déploie que des `tags` forcés) : pousser un commit ou forcer les `tags` |
| `Determine changed files` : avertissement « no usable last successful push run » | premier run, plus aucun run réussi dans l'API ou historique réécrit : seul ce push est déployé, les runs annulés ou rouges d'avant ne sont pas rattrapés (les relancer à la main, `workflow_dispatch` avec `tags`) |

Reproduire en local, sans rien changer :

```bash
cd ansible
ansible-playbook docker.yml --tags <tag> --check --diff
```

## Réparation

- **Revenir en arrière** sur une PR qui casse : un revert, par une PR, comme
  le reste. Pousser la branche ne déploie rien ; le revert arrivé sur `main`
  (merge, ou push direct en urgence) se déploie comme tout push : il redéploie
  l'ancien état ; l'ancienne image est souvent encore là, `dc@` ne la
  retélécharge pas. Ce que le merge ne déploie pas, le revert non plus : un
  module Tofu (`tofu apply`), un rôle de `nas.yml`, `pve.yml` ou `lxc.yml`, le
  sous-module `secrets/`, et un changement de playbook annulé après un run
  rouge, nul au net ([conventions/ci.md](../conventions/ci.md)), se rejouent à
  la main. Une image de la liste blanche de Renovate : la retirer dans la même
  PR (voir [Prévention](#prevention)), sinon le lundi suivant la refusionne.

  Le dépôt fusionne en rebase seulement : pas de commit de merge, une PR de
  plusieurs commits en pose autant sur `main`, sans numéro de PR dans le
  message et sous d'autres sha que ceux de `gh pr view --json commits`. Il faut
  les annuler tous : un revert partiel se déploie tel quel au merge. La PR
  donne les bornes : `merge_commit_sha` est son dernier commit sur `main`, et
  le rebase y pose le bloc d'un seul tenant ; le nombre est celui de ses
  commits hors merges (le rebase les retire). Depuis le checkout principal,
  que `git fetch` ne modifie pas :

  ```bash
  pr=<numéro>
  git fetch origin
  tete=$(gh api "repos/{owner}/{repo}/pulls/$pr" --jq .merge_commit_sha)
  sujets=$(gh api --paginate "repos/{owner}/{repo}/pulls/$pr/commits" \
    --jq '.[] | select(.parents | length == 1) | .commit.message | split("\n")[0]')
  n=$(wc -l <<<"$sujets")
  diff <(echo "$sujets") <(git log --reverse --format=%s -n "$n" "$tete") &&
    git log --format='%h %s' -n "$n" "$tete"
  ```

  `diff` muet et la liste affichée : les bornes sont bonnes. Il ne compare que
  les sujets. Un écart interdit de lancer le revert, il se lit dans
  `git log "$tete"`. Les 672 PR fusionnées de la #432 à la #1150 passent
  (263 de plusieurs commits). Ce qui le fait échouer : un commit vidé par le
  rebase, donc absent de `main` (#426, #427, #431, « Initial plan » :
  recompter à la main) ; une PR fusionnée par un commit de merge (jusqu'à la
  #416 : `git revert -m 1 "$tete"`) ; après le passage au squash
  ([commits-signes.md](commits-signes.md)), une PR dont `$tete` est alors le
  seul commit à annuler (`git revert --no-edit "$tete"`).

  Le revert, dans le même shell (il reprend `$tete` et `$n`) et un worktree
  partant d'`origin/main` :

  ```bash
  git worktree add -b revert/<sujet> ../homelab-revert origin/main
  cd ../homelab-revert
  git revert --no-edit "$tete~$n..$tete"   # du plus récent au plus ancien
  git rev-list --count origin/main..HEAD   # doit valoir $n
  git push -u origin revert/<sujet>
  gh pr create --fill
  ```

  Une PR postérieure a touché les mêmes lignes : `git revert` s'arrête en
  conflit, les commits déjà annulés restent sur la branche. Résoudre,
  `git add`, `git revert --continue` ; ni `--skip` ni push à ce stade, ce
  serait le revert partiel (`git revert --abort` pour renoncer). Seule
  exception : `--continue` répond « rien à valider », ce commit n'a plus rien
  à annuler (déjà défait par une PR postérieure, ou montée seule de
  `secrets/` dont on garde la révision de `main`). `--skip` passe alors au
  suivant, et le compte attendu perd un par commit sauté.

  Ce worktree ne lit aucun secret : par exception à la règle d'`AGENTS.md`,
  inutile d'y initialiser `secrets/`. Le revert d'une montée du sous-module
  ramène sa révision d'avant (à regarder : `git diff origin/main -- secrets`) ;
  si la PR portait une rotation, le déploiement suivant réécrirait l'ancienne
  valeur. `git checkout origin/main -- secrets` garde celle de `main`, puis
  `git commit` hors conflit (un commit de plus au compte) ; sur un conflit, il remplace le `git add secrets`
  suggéré par git, qui échoue sur un sous-module non initialisé. Le merge
  passé, depuis le checkout principal :
  `git worktree remove ../homelab-revert && git branch -D revert/<sujet>`
  (`remove` refuse sans `--force` un worktree au sous-module initialisé).

  Attention aux montées qui migrent des données (base, appli qui modifie son
  schéma au démarrage) : revenir à l'ancienne image ne défait pas la
  migration. Il faut alors restaurer les données
  ([sauvegarde-et-restauration.md](sauvegarde-et-restauration.md)) en même
  temps.
- **Urgence** : l'admin peut pousser directement sur `main` (contournement du
  ruleset) ; le push déclenche le même déploiement. À réserver aux cas où
  attendre la CI coûte plus que le risque. Si le ruleset
  `main-signed-commits` est actif, ce contournement ne le couvre pas : le
  commit doit porter ma signature SSH ([commits-signes.md](commits-signes.md)).
- **Relancer un déploiement** sans nouveau commit :

  ```bash
  gh workflow run deploy-docker-app.yaml -f playbook=docker -f tags=rss
  ```

  (`playbook` : `all`, `docker`, `pi`, `pangolin` ou `flip`.)
- **Déployer depuis le poste** (CI en panne) :
  `ansible-playbook docker.yml --tags rss`, après un `--check --diff`.
- **Secrets de la CI à refaire** (clé age, clé SSH de déploiement,
  identifiants OLM) : ils viennent de `tofu/github` (`environments.tf`,
  `ssh_key.tf`) ; `tofu plan` puis `tofu apply` dans
  `tofu/github`. Une nouvelle clé SSH réécrit `keys/github-actions.pub` : la
  committer avec sa nouvelle empreinte dans `ssh_login_notify_known_fingerprints`
  (défauts du rôle, sinon chaque déploiement sonne sur Telegram et le scénario
  Molecule échoue) et dans `ci_key_audit_fingerprint` (défauts du rôle, sinon ce
  contrôle se dit aveugle et son scénario échoue), puis rejouer `00-setup.yaml`
  sur les hôtes et `docker.yml --tags ci_key_audit`.

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
  blanche, et des correctifs des GitHub Actions), dès que le ruleset a ses
  checks verts. Molecule ne tire aucune image : ces checks ne prouvent pas
  qu'elle démarre. Une image introuvable rend le déploiement rouge ; une image
  qui démarre puis plante le laisse vert (`dc@` est actif dès que
  `docker compose up` tourne) : c'est le moniteur Uptime Kuma de l'appli qui
  passe DOWN. Dans les deux cas, revenir au digest précédent par une PR
  (`git revert` du commit) **et**, dans la même PR, retirer l'image de la
  liste blanche : sans cela, Renovate repropose le même digest le lundi
  suivant et le refusionne seul. Toute montée majeure (hors nos images)
  attend une case cochée sur le Dependency Dashboard (la MariaDB officielle
  de Nextcloud n'en voit aucune : elle reste sur la LTS 12.3, et son Redis
  `-bookworm` sur la 8.2).
- Une PR qui touche `path_bypass_images.json` ne fusionne jamais seule :
  relire les notes de version et les sources de `reread` de l'entrée
  (la note de la PR le rappelle) avant de la merger à la main.

## Tests hebdomadaires rouges

Sur une PR, `test.yaml` ne lance que les scénarios Molecule et les modules
Tofu qu'atteignent les fichiers modifiés (`.github/scripts/select_tests.py`,
le résumé du job `Discover test suites` dit pourquoi). La matrice complète
tourne chaque lundi à 03:30 UTC sur `main` : elle rattrape ce que la sélection
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
- **Une suite rouge au run planifié mais verte sur sa PR** : la sélection l'a sautée.
  Corriger la suite, puis apprendre la dépendance manquée à
  `select_tests.py` (et un cas à `test_select_tests.py`).
- **Matrice complète sur une PR** : poser le label `full-tests`, ou
  `gh workflow run test.yaml --ref <branche>`.
