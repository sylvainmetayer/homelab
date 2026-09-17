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
