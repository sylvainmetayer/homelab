# Le dépôt 1y existe depuis 2020 (copie du modèle nhoizey/1y) : il est importé,
# pas créé. Les réglages sont alignés sur tofu/ref ; le premier plan montre donc
# des modifications en place (wiki, projets, merge commits…), pas de création.
import {
  to = github_repository.r
  id = var.repository
}

resource "github_repository" "r" {
  name         = var.repository
  description  = "Gestionnaire d'URL courtes - ${local.hostname}"
  homepage_url = "https://${local.hostname}"
  visibility   = "public"

  topics = ["eleventy", "cloudflare-pages", "url-shortener"]

  has_issues      = true
  has_wiki        = false
  has_projects    = false
  has_discussions = false

  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = true
  delete_branch_on_merge = true

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

resource "github_repository_vulnerability_alerts" "r" {
  repository = github_repository.r.name
  enabled    = true
}

# Alertes oui, PR automatiques non : Renovate (renovate.json du dépôt) gère les
# montées de version, Dependabot en ouvrirait des doublons.
resource "github_repository_dependabot_security_updates" "r" {
  repository = github_repository.r.name
  enabled    = false

  depends_on = [github_repository_vulnerability_alerts.r]
}

# Jeton des workflows en lecture seule par défaut : le dépôt n'en a aucun, un
# workflow ajouté plus tard sans bloc `permissions:` n'écrira rien.
resource "github_workflow_repository_permissions" "r" {
  repository                       = github_repository.r.name
  default_workflow_permissions     = "read"
  can_approve_pull_request_reviews = false
}

# Pas de PR obligatoire (les liens s'ajoutent en poussant sur master) : on
# protège seulement contre la perte d'historique, propriétaire compris.
resource "github_branch_protection" "r_master" {
  repository_id = github_repository.r.node_id
  pattern       = var.production_branch

  enforce_admins      = true
  allows_deletions    = false
  allows_force_pushes = false
}

# PUT /user/installations/{id}/repositories/{repo_id}, qui n'accepte qu'un PAT
# classique avec le scope repo (pas le jeton OAuth de `gh auth token`) : voir
# README.md. Même mécanique pour les deux apps.
resource "github_app_installation_repository" "cloudflare" {
  count = var.cloudflare_github_installation_id == null ? 0 : 1

  installation_id = var.cloudflare_github_installation_id
  repository      = github_repository.r.name
}

resource "github_app_installation_repository" "renovate" {
  count = var.renovate_github_installation_id == null ? 0 : 1

  installation_id = var.renovate_github_installation_id
  repository      = github_repository.r.name
}
