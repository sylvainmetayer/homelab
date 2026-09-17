# The public repository that succeeds sylvainmetayer/flip-planning. It is
# created empty on purpose: the history it will receive is the one rewritten
# by the filter-repo pass (flip-planning#198), pushed by hand afterwards.
#
# sylvainmetayer/flip-planning#286 collects the settings that "do not travel
# with a git push". This file covers the ones the GitHub provider can set;
# the rest (fork pull request workflow approval, private vulnerability
# reporting, GHCR package visibility, Renovate and GitGuardian) have no
# provider resource in integrations/github 6.x and are listed as manual steps
# in README.md next to this file.
resource "github_repository" "planning_equipes" {
  name        = var.planning_equipes_repository
  description = "Affectation automatique d'animateurs aux stands d'un événement, sous contrainte légale, de compétences, de disponibilités et d'équité de charge"
  visibility  = var.planning_equipes_visibility

  topics = [
    "planning",
    "scheduling",
    "timefold",
    "quarkus",
    "angular",
  ]

  # No initial commit: the first push is a rewritten history, and an
  # auto-generated README here would make it a force-push over a foreign root.
  auto_init = false

  has_issues      = true
  has_wiki        = false
  has_projects    = false
  has_discussions = false

  # git-cliff reads conventional commits off main (flip-planning#248), so keep
  # merge commits available and make squash titles carry the pull request title
  # rather than "Merge pull request #n".
  allow_merge_commit          = false
  allow_squash_merge          = true
  allow_rebase_merge          = true
  allow_auto_merge            = true
  allow_update_branch         = true
  delete_branch_on_merge      = true
  squash_merge_commit_title   = "PR_TITLE"
  squash_merge_commit_message = "COMMIT_MESSAGES"

  # Same contract as the "Certificat d'origine (DCO)" check: a commit authored
  # from the web UI is signed off too, instead of failing the check afterwards.
  web_commit_signoff_required = true

  # Secret scanning and push protection are free on public repositories only;
  # on a private one without GitHub Advanced Security the API rejects them, so
  # the block appears with the public switch.
  dynamic "security_and_analysis" {
    for_each = var.planning_equipes_visibility == "public" ? [1] : []

    content {
      secret_scanning {
        status = "enabled"
      }

      secret_scanning_push_protection {
        status = "enabled"
      }
    }
  }

  # Deleting this repository deletes its issues, its releases and the URLs
  # printed on distributed PDFs. Archiving is the destructive path we accept.
  archive_on_destroy = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "github_repository_vulnerability_alerts" "planning_equipes" {
  repository = github_repository.planning_equipes.name
  enabled    = true
}

# Alerts yes, automatic pull requests no: Renovate owns dependency bumps here,
# and four of its rules gate majors behind dependencyDashboardApproval
# (flip-planning#286). Dependabot opening its own pull requests would walk
# straight past that gate.
resource "github_repository_dependabot_security_updates" "planning_equipes" {
  repository = github_repository.planning_equipes.name
  enabled    = false
}

# Every workflow in the repository declares its own `permissions:` block, so a
# read-only default token costs nothing and closes the door on a workflow added
# later without one.
resource "github_workflow_repository_permissions" "planning_equipes" {
  repository                       = github_repository.planning_equipes.name
  default_workflow_permissions     = "read"
  can_approve_pull_request_reviews = false
}

resource "github_branch_protection" "planning_equipes_main" {
  repository_id = github_repository.planning_equipes.node_id
  pattern       = "main"

  # Pull requests become the way in, but with zero required approvals: a solo
  # maintainer cannot be approved by anyone else. enforce_admins stays false so
  # the history rewrite can still be pushed to main, and so an emergency fix is
  # not gated on a review that will never come.
  enforce_admins = false

  required_pull_request_reviews {
    required_approving_review_count = 0
    dismiss_stale_reviews           = true
    require_last_push_approval      = false
  }

  require_conversation_resolution = true
  allows_deletions                = false
  allows_force_pushes             = false

  # Empty by default, see the variable: a required check that never reports
  # leaves every pull request pending forever.
  dynamic "required_status_checks" {
    for_each = length(var.planning_equipes_required_checks) > 0 ? [1] : []

    content {
      strict   = true
      contexts = var.planning_equipes_required_checks
    }
  }
}

# ---------------------------------------------------------------------------
# Immutabilité des releases.
#
# "Disallow assets and tags from being modified once a release is published":
# sans elle, un tag de release peut être redéplacé sur un autre commit et une
# archive remplacée sous la même URL, sans que rien ne bouge côté git. C'est
# précisément ce que le rôle Ansible flip_planning consomme en aval
# (ghcr.io/sylvainmetayer/planning-equipes + assets de release).
#
# integrations/github 6.13.0 n'a ni attribut sur `github_repository` ni
# ressource dédiée : les deux PR ajoutant `github_repository_immutable_releases`
# (integrations/terraform-provider-github#3447 puis #3574) ont été fermées sans
# merge, et la demande #2746 est toujours ouverte. L'API REST, elle, existe :
# GET/PUT/DELETE /repos/{owner}/{repo}/immutable-releases.
#
# Plutôt que d'ajouter une ligne de plus à la liste des réglages manuels du
# README - dont aucun ne se signale quand il manque - on lit l'état réel à
# chaque plan et on le remet en place quand il a dérivé. Le jour où le provider
# expose la ressource, ces deux blocs se remplacent par un `moved`/import.
#
# Dépendance : la CLI `gh`, qui porte son propre jeton. Le README demande déjà
# `export GITHUB_TOKEN="$(gh auth token)"` avant tout `tofu plan` ici.
# ---------------------------------------------------------------------------
data "external" "planning_equipes_immutable_releases" {
  # `--jq` est celui intégré à gh (pas de binaire jq à installer) ; le data
  # source external exige une map de *chaînes*, d'où les `tostring` sur des
  # champs qui sont des booléens côté API.
  program = [
    "gh", "api",
    "repos/${var.github_owner}/${var.planning_equipes_repository}/immutable-releases",
    "--jq", "{enabled: (.enabled|tostring), enforced_by_owner: (.enforced_by_owner|tostring)}",
  ]

  # Au premier apply le dépôt n'existe pas encore : sans ce depends_on, la
  # lecture partirait au plan et échouerait en 404. Avec, elle est repoussée à
  # l'apply, après la création.
  depends_on = [github_repository.planning_equipes]
}

resource "terraform_data" "planning_equipes_immutable_releases" {
  # L'état live fait partie du déclencheur : si le réglage est décoché dans
  # l'interface, la lecture ci-dessus renvoie "false" au plan suivant, la
  # ressource est remplacée et le PUT le réactive. C'est ce qui distingue ce
  # bloc d'un simple provisioner joué une fois à la création.
  triggers_replace = {
    repository = github_repository.planning_equipes.name
    live       = data.external.planning_equipes_immutable_releases.result.enabled
  }

  # PUT idempotent : rejouer sur un dépôt déjà immuable est un no-op côté API.
  provisioner "local-exec" {
    command = join(" ", [
      "gh", "api", "--method", "PUT",
      "repos/${var.github_owner}/${var.planning_equipes_repository}/immutable-releases",
      "--silent",
    ])
  }

  # Retirer ce bloc ne redésactive rien : le `destroy` ne joue aucun DELETE,
  # volontairement. Désactiver l'immutabilité est une opération à faire à la
  # main, en connaissance de cause.
}
