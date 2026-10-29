resource "github_repository" "this" {
  name         = var.repository
  description  = var.description
  homepage_url = coalesce(var.homepage_url, "https://${local.hostname}")
  visibility   = "public"

  topics = var.topics

  auto_init = var.auto_init

  has_issues      = true
  has_wiki        = false
  has_projects    = var.has_projects
  has_discussions = false

  allow_merge_commit     = var.allow_merge_commit
  allow_squash_merge     = true
  allow_rebase_merge     = true
  allow_auto_merge       = var.allow_auto_merge
  delete_branch_on_merge = var.delete_branch_on_merge

  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }

    secret_scanning_push_protection {
      status = "enabled"
    }
  }

  archive_on_destroy = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "github_repository_vulnerability_alerts" "this" {
  repository = github_repository.this.name
  enabled    = true
}

resource "github_repository_dependabot_security_updates" "this" {
  repository = github_repository.this.name
  enabled    = var.dependabot_security_updates

  depends_on = [github_repository_vulnerability_alerts.this]
}

# Jeton des workflows en lecture seule par défaut : un workflow ajouté plus tard
# sans bloc `permissions:` n'écrit rien dans ce dépôt public.
resource "github_workflow_repository_permissions" "this" {
  count = var.restrict_workflow_token ? 1 : 0

  repository                       = github_repository.this.name
  default_workflow_permissions     = "read"
  can_approve_pull_request_reviews = false
}

# Pas de PR obligatoire (Sveltia CMS commite sur main pour ref, les liens de 1y
# s'ajoutent en poussant) : seulement contre la perte d'historique, y compris
# pour le propriétaire, seul à pousser.
resource "github_branch_protection" "production" {
  count = var.protect_production_branch ? 1 : 0

  repository_id = github_repository.this.node_id
  pattern       = var.production_branch

  enforce_admins      = true
  allows_deletions    = false
  allows_force_pushes = false
}

# Donne accès au dépôt à l'app GitHub de Cloudflare, déjà installée sur le
# compte : la première installation exige un consentement dans le navigateur,
# aucune API ne la fait. PUT /user/installations/{id}/repositories/{repo_id},
# qui n'accepte qu'un PAT classique avec le scope repo (pas le jeton OAuth de
# `gh auth token`) : voir tofu/ref/README.md.
resource "github_app_installation_repository" "cloudflare" {
  count = var.cloudflare_github_installation_id == null ? 0 : 1

  installation_id = var.cloudflare_github_installation_id
  repository      = github_repository.this.name
}
