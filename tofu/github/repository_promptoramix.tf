# Promptoramix, the AI bot (Rust) of the Marmelab Linkx tournament. Its CI
# publishes ghcr.io/sylvainmetayer/promptoramix:main on every push to main,
# which ansible/roles/promptoramix deploys on flip (Renovate bumps the digest).
#
# Public from the start: nothing in its history is secret (the HMAC secret
# lives in ansible/secrets.sops.yaml only). Same protections as
# repository_planning_equipes.tf; the settings the provider cannot reach
# (GHCR package visibility, Renovate) are manual steps in README.md.
resource "github_repository" "promptoramix" {
  name        = var.promptoramix_repository
  description = "IA Promptoramix pour le tournoi Linkx de Marmelab (Rust)"
  visibility  = "public"

  topics = [
    "rust",
    "linkx",
    "game-ai",
    "marmelab",
  ]

  # No initial commit: the existing local history is pushed as is, and an
  # auto-generated README here would make that push a force-push over a
  # foreign root.
  auto_init = false

  has_issues      = true
  has_wiki        = false
  has_projects    = false
  has_discussions = false

  allow_merge_commit          = false
  allow_squash_merge          = true
  allow_rebase_merge          = true
  allow_auto_merge            = true
  allow_update_branch         = true
  delete_branch_on_merge      = true
  squash_merge_commit_title   = "PR_TITLE"
  squash_merge_commit_message = "COMMIT_MESSAGES"

  # Free on public repositories.
  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }

    secret_scanning_push_protection {
      status = "enabled"
    }
  }

  # Archiving is the destructive path we accept, not a deletion.
  archive_on_destroy = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "github_repository_vulnerability_alerts" "promptoramix" {
  repository = github_repository.promptoramix.name
  enabled    = true
}

# Alerts yes, automatic pull requests no: Renovate owns dependency bumps
# (renovate.json of the repository).
resource "github_repository_dependabot_security_updates" "promptoramix" {
  repository = github_repository.promptoramix.name
  enabled    = false
}

# The CI workflow declares its own `permissions:` (packages: write on the
# image job only): a read-only default token costs nothing.
resource "github_workflow_repository_permissions" "promptoramix" {
  repository                       = github_repository.promptoramix.name
  default_workflow_permissions     = "read"
  can_approve_pull_request_reviews = false
}

# Same rules as planning-equipes' main: pull requests with zero required
# approvals (a solo maintainer), no deletion nor force-push. enforce_admins
# stays false, so the first push of the existing history and an urgent fix
# during the tournament go straight to main. No required check: a check that
# never reports would leave every pull request pending.
resource "github_branch_protection" "promptoramix_main" {
  repository_id = github_repository.promptoramix.node_id
  pattern       = "main"

  enforce_admins = false

  required_pull_request_reviews {
    required_approving_review_count = 0
    dismiss_stale_reviews           = true
    require_last_push_approval      = false
  }

  require_conversation_resolution = true
  allows_deletions                = false
  allows_force_pushes             = false
}
