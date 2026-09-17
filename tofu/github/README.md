# tofu/github

Ce module porte deux choses sans rapport entre elles :

- les **secrets Actions du dépôt `homelab`** (clé Age SOPS, clé SSH de
  déploiement, identifiants OLM lus dans l'état de `pangolin_config`) ;
- le **dépôt `planning-equipes`**, successeur public de `flip-planning`, et
  les réglages de son `main` — voir
  [sylvainmetayer/flip-planning#286](https://github.com/sylvainmetayer/flip-planning/issues/286).

```bash
export GITHUB_TOKEN="$(gh auth token)"   # jeton avec les droits admin sur le dépôt
tofu -chdir=tofu/github init
tofu -chdir=tofu/github plan
```

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
  `flip_planning_ghcr_token` de `ansible/secrets.sops.yaml`, qui demande `sops`.
- [ ] **Transférer les issues** de `planning-equipes-private`, puis supprimer
  ce dépôt de dépannage.
