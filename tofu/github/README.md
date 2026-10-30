# tofu/github

Ce module porte quatre choses sans rapport entre elles :

- les **environnements Actions du dépôt `homelab`** et leurs secrets (clé
  Age SOPS, clé SSH de déploiement, identifiants OLM lus dans l'état de
  `pangolin_config`, accès du test de restauration, URL push, jeton ntfy de
  la CI), voir plus bas ;
- le **dépôt `planning-equipes`**, successeur public de `flip-planning`, et
  les réglages de son `main` — voir
  [sylvainmetayer/flip-planning#286](https://github.com/sylvainmetayer/flip-planning/issues/286) ;
- le **dépôt `promptoramix`**, l'IA (Rust) du tournoi Linkx de Marmelab, dont
  l'image `ghcr.io/sylvainmetayer/promptoramix:main` est déployée sur flip par
  `ansible/roles/promptoramix` — voir [plus bas](#dépôt-promptoramix) ;
- le **dépôt privé `homelab-secrets`** (fichiers SOPS et inventaire de
  rotation, [ADR 0018](../../docs/adr/0018-secrets-depot-prive.md)), sa clé
  de déploiement en lecture seule et le secret `HOMELAB_SECRETS_SSH_KEY` de
  `homelab` — voir [plus bas](#dépôt-homelab-secrets).

La branche `main` du dépôt `homelab` porte deux rulesets
(`ruleset_homelab.tf`) : `main` (PR obligatoire, checks requis, ni
force-push ni suppression, contournable par l'admin) et, si
`homelab_require_signed_commits` vaut `true`, `main-signed-commits`
(commits signés, **sans** contournement). Ce second ruleset est incompatible
avec le « Rebase and merge » de GitHub, qui ne signe pas les commits qu'il
réécrit : la précondition refuse le plan tant que le rebase est permis. La
bascule (signature SSH du poste, clé de signature GitHub, passage au squash)
est dans [docs/runbooks/commits-signes.md](../../docs/runbooks/commits-signes.md).

Les environnements Actions du dépôt (`production`, `restore-test`,
`storage-box-quota`, `secrets-rotation`, `ntfy-github`) et leurs secrets
sortent tous d'une seule table, `local.environments` d'`environments.tf`
(nom de l'environnement → nom du secret → valeur) : un environnement de plus
est une entrée de plus, lisible depuis `main` seulement comme les autres.

L'environnement **`storage-box-quota`** (workflow `storage-box-quota.yaml`)
lit la clé SOPS `hcloud_readonly_token` de `secrets/ansible.sops.yaml`, qui
ne se crée qu'à la main, avant le premier
plan qui la cite : Console Hetzner, projet de la Storage Box, Security → API
tokens, permission **Read**, puis
`printf '"%s"' "$jeton" | sops set --value-stdin secrets/ansible.sops.yaml '["hcloud_readonly_token"]'`.
Jamais le `HCLOUD_TOKEN` de `tofu/pangolin`, en lecture-écriture. Son URL push est l'output
`uptime_storage_box_quota_url` de `tofu/pangolin_config` : appliquer ce module
avant le plan d'ici, qui échoue sinon sur un attribut absent.

L'environnement **`secrets-rotation`** (workflow `secrets-rotation.yaml`,
échéances de `secrets/secrets-rotation.yaml`) ne porte que l'URL push du moniteur
« Rotation des secrets », output `uptime_secrets_rotation_url` de
`tofu/pangolin_config` : même ordre, `pangolin_config` appliqué d'abord.

L'environnement **`ntfy-github`** (job `notify` de `trivy.yaml` et
`renovate-digest.yaml`, le bilan Renovate du lundi) ne porte que
`NTFY_GITHUB_TOKEN`, le jeton du producteur ntfy `github`, clé SOPS
`ntfy_github_token` de `secrets/ansible.sops.yaml` (écriture seule sur le
topic `github`, rôle `ntfy`) : tout ce que publie la CI passe par ce
producteur, jamais par le `scripts` des hôtes, et ntfy ne l'accepte qu'une
fois `docker.yml --tags ntfy` déployé.

Renommer un environnement (clé de `local.environments`) le détruit sur
GitHub avec ses secrets, puis en crée un neuf : fusionner la PR qui change
l'`environment:` des workflows, **puis** appliquer aussitôt, entre deux runs
planifiés. Un job qui cite un environnement absent le fait créer par GitHub,
vide et sans politique de branche : avant l'apply, le nouveau nom (adopté
ensuite par l'apply, qui y pose politique et secrets) ; après un apply fait
avant le merge, l'ancien à nouveau, à supprimer à la main (Settings →
Environments). Un `moved` vers la nouvelle clé ne fait que lier le
remplacement dans le plan ; il se retire une fois appliqué.

```bash
export GITHUB_TOKEN="$(gh auth token)"   # jeton avec les droits admin sur le dépôt
tofu -chdir=tofu/github init
tofu -chdir=tofu/github plan
```

La CLI `gh` doit être installée et authentifiée : l'immutabilité des releases
n'a pas de ressource dans le provider et passe par elle (lecture à chaque plan,
`PUT` à l'apply). Sans `gh` dans le `PATH`, le plan s'arrête.

## Ce que terraform pose sur `planning-equipes`

| Réglage | Ressource |
|---|---|
| Création du dépôt, visibilité, description, sujets, options de fusion | `github_repository.planning_equipes` |
| Signature obligatoire des commits faits depuis l'interface web (pendant du DCO) | idem, `web_commit_signoff_required` |
| Scan de secrets + protection à la poussée | idem, bloc `security_and_analysis` (visibilité publique uniquement) |
| Alertes Dependabot | `github_repository_vulnerability_alerts.planning_equipes` |
| Mises à jour Dependabot automatiques, **désactivées** au profit de Renovate | `github_repository_dependabot_security_updates.planning_equipes` |
| `GITHUB_TOKEN` en lecture seule par défaut | `github_workflow_repository_permissions.planning_equipes` |
| Protection de `main` : PR obligatoire, pas de suppression ni de force-push, conversations résolues | `github_branch_protection.planning_equipes_main` |
| Immutabilité des releases (tags et assets figés une fois publiés) | `terraform_data.planning_equipes_immutable_releases`, via `gh` |
| Checks requis sur `main` | même ressource, via `planning_equipes_required_checks` |

Deux valeurs sont volontairement en retrait, et c'est là qu'il faut revenir :

- `planning_equipes_visibility` vaut `private`. **Ne la passer à `public`
  qu'une fois l'historique réécrit** (flip-planning#198) et poussé : un dépôt
  public est cloné et forké en quelques secondes, et le repasser privé ne
  rappelle pas les copies.
- `planning_equipes_required_checks` est vide. Un check requis qui ne
  s'exécute jamais laisse la PR éternellement en attente : `dco.yml` n'existe
  pas encore (flip-planning#228), et les jobs `test`, `frontend`, `scenario`,
  `e2e` et `securite` portent un `if:` **au niveau du job** qui les saute sur
  les PR de fork. Remplir la liste une fois ces deux points réglés, en
  déplaçant les conditions du job vers ses étapes.

`enforce_admins` reste à `false` : c'est ce qui permet de pousser l'historique
réécrit sur `main` malgré la protection, et de corriger en urgence sans
attendre une revue qui ne viendra pas.

## Ordre des opérations

1. `tofu apply` — le dépôt est créé **vide et privé** (pas de commit initial :
   l'historique réécrit arrive par une poussée, pas par un `auto_init`).
2. Pousser l'historique issu du `filter-repo` (flip-planning#198).
3. Vérifier que la branche par défaut est bien `main` — pour un dépôt créé
   vide, elle vient du réglage de compte
   (<https://github.com/settings/repositories>), pas du terraform.
4. Faire les réglages manuels ci-dessous **avant** la bascule publique.
5. Passer `planning_equipes_visibility` à `public`, `tofu apply`.

## Ce qui reste à la main

Le provider `integrations/github` 6.x n'a pas de ressource pour ces réglages.
Aucun ne se signale de lui-même quand il manque, d'où cette liste.

(L'immutabilité des releases est dans le même cas - les PR
`github_repository_immutable_releases`
[#3447](https://github.com/integrations/terraform-provider-github/pull/3447) et
[#3574](https://github.com/integrations/terraform-provider-github/pull/3574)
ont été fermées sans merge, la demande
[#2746](https://github.com/integrations/terraform-provider-github/issues/2746)
reste ouverte - mais elle est tenue par `gh` depuis le terraform, pas à la main.)

### Avant la bascule publique

- [ ] **Approbation des workflows sur les PR de fork** —
  `Settings → Actions → General → Fork pull request workflows from outside
  collaborators` → « Require approval for all outside collaborators ».
  Le défaut de GitHub n'exige une approbation que des primo-contributeurs :
  une seconde PR du même compte part toute seule.
- [ ] **Signalement de vulnérabilité privé** —
  `Settings → Code security → Private vulnerability reporting`.
  `.github/SECURITY.md` et `.github/ISSUE_TEMPLATE/config.yml` renvoient tous
  deux vers `/security/advisories/new` : sans ce réglage ces liens mènent à
  une page inaccessible, et la première faille sera signalée dans une issue
  publique.
- [ ] **Installer Renovate** sur le dépôt (<https://github.com/apps/renovate>).
  Son tableau de bord conditionne les quatre règles
  `dependencyDashboardApproval` : sans l'issue de tableau de bord, ces montées
  deviennent inapprouvables.
- [ ] **Installer GitGuardian** sur le dépôt. Sans installation, le contrôle
  disparaît **en silence** de la liste des checks.
- [ ] **Vérifier la liste des checks de la première PR** du dépôt neuf, avant
  de remplir `planning_equipes_required_checks`.

### Après la bascule

- [ ] **Visibilité du paquet GHCR** —
  `https://github.com/users/sylvainmetayer/packages/container/planning-equipes/settings`
  → visibilité publique, pour que l'image soit tirable.
- [x] **Repointer le rôle Ansible** `ansible/roles/flip_planning` de ce dépôt :
  il déploie désormais `ghcr.io/sylvainmetayer/planning-equipes`. Le paquet étant
  public, le `docker login` du rôle a disparu avec lui — reste à retirer
  `flip_planning_ghcr_token` de `secrets/ansible.sops.yaml`, qui demande `sops`.
- [ ] **Transférer les issues** de `planning-equipes-private`, puis supprimer
  ce dépôt de dépannage.

## Dépôt `promptoramix`

`repository_promptoramix.tf` pose les mêmes réglages que pour
`planning-equipes` (public d'emblée, scan de secrets et protection à la
poussée, alertes Dependabot sans PR automatiques, `GITHUB_TOKEN` en lecture
seule, `main` protégée : PR sans approbation requise, ni suppression ni
force-push, `enforce_admins = false`), sans immutabilité des releases (le
dépôt n'en publie pas) ni check requis.

### Ordre des opérations

1. `tofu apply` — le dépôt est créé **vide** (`auto_init = false`).
2. Pousser l'historique local existant sur `main` : la CI publie alors
   `ghcr.io/sylvainmetayer/promptoramix:main` (et `sha-<commit>`).
3. Faire les réglages manuels ci-dessous.

### Ce qui reste à la main

- [ ] **Visibilité du paquet GHCR** —
  `https://github.com/users/sylvainmetayer/packages/container/promptoramix/settings`
  → visibilité publique. Un paquet poussé par Actions naît **privé** : sans
  ce réglage, flip ne peut pas tirer l'image (le rôle ne fait aucun
  `docker login`) et Renovate ne voit aucun digest à épingler.
- [ ] **Installer Renovate** sur le dépôt (<https://github.com/apps/renovate>),
  qui porte son `renovate.json`.
- [ ] **Installer GitGuardian** sur le dépôt, comme sur les autres.

## Dépôt `homelab-secrets`

`repository_homelab_secrets.tf` crée le dépôt **privé** qui porte
`secrets.sops.yaml`, `ansible.sops.yaml` et `secrets-rotation.yaml`, monté
en sous-module à `secrets/` dans `homelab`
([ADR 0018](../../docs/adr/0018-secrets-depot-prive.md)). Le compte est en
GitHub Free : ni ruleset ni protection de branche sur un dépôt privé (403).
Il tient par : aucun collaborateur, Actions désactivées
(`github_actions_repository_permissions`), une seule clé de déploiement,
**en lecture seule** (`github_repository_deploy_key.homelab_secrets_ci`),
dont la clé privée devient le secret **du dépôt** `homelab`
`HOMELAB_SECRETS_SSH_KEY` : pas d'un environnement (ceux d'ici ne sont
lisibles que depuis `main`), car le Lint des PR doit lire les fichiers. Une branche du dépôt
`homelab` le reçoit (Renovate compris), une PR de fork non.

Rotation de la clé : `tofu apply -replace=tls_private_key.homelab_secrets_deploy`
(clé publique et secret suivent dans le même apply).

### Ordre des opérations

1. `tofu apply` ici : dépôt vide, clé de déploiement, secret Actions. Rien ne
   les lit encore.
2. Pousser les trois fichiers dans le dépôt neuf (renommés, voir la PR de
   bascule et `docs/conventions/secrets.md`).
3. Fusionner la PR de bascule de `homelab` (sous-module `secrets/`, chemins,
   workflows), puis `git submodule update --init` sur chaque poste.


## Summary (moved from `AGENTS.md`)

`tofu/github/` — GitHub-side config: the Actions secrets of this repo (SOPS Age key, CI deploy key, OLM credentials read from `pangolin_config`'s state; the `restore-test` environment's secrets, from `tofu/pangolin`'s and `pangolin_config`'s states and `backup_passphrase`; the `storage-box-quota` environment's, `hcloud_readonly_token` and `pangolin_config`'s `uptime_storage_box_quota_url`; the `secrets-rotation` environment's, `pangolin_config`'s `uptime_secrets_rotation_url` only; the `ntfy-github` environment's (Trivy's `notify` job and the Renovate digest), the ntfy token `ntfy_github_token` only as `NTFY_GITHUB_TOKEN`: every CI publisher uses the `github` producer, never the hosts' `scripts`; every environment, its `main`-only branch policy and its secrets come from one table, `local.environments` in `environments.tf`, through `for_each`) and the `planning-equipes` and `promptoramix` repositories themselves — creation, visibility, `main` branch protection; plus the private `homelab-secrets` repository (ADR 0018: SOPS files and rotation inventory, submodule `secrets/`), Actions disabled, its read-only deploy key whose private key is the **repository** (not environment) secret `HOMELAB_SECRETS_SSH_KEY`, so PR Lint can clone it. This repo's `main` has two rulesets (`ruleset_homelab.tf`): `main` (PR, required checks, admin bypass) and, once `homelab_require_signed_commits` is true, `main-signed-commits` (signed commits, no bypass). GitHub cannot sign a "Rebase and merge", so that switch needs PRs merged by squash (`gh pr merge --squash`); its precondition refuses the plan while rebase merging is allowed (`docs/runbooks/commits-signes.md`). The settings the provider can't reach (fork PR approval, private vulnerability reporting, GHCR package visibility, Renovate/GitGuardian) are a checklist in `tofu/github/README.md`.
