# Le dépôt existe depuis 2017 : il est importé, pas créé. Les réglages
# reprennent l'existant tel quel (description, méthodes de fusion…) ; seuls
# s'ajoutent le scan de secrets, les alertes Dependabot et le ruleset de main,
# pour la note OpenSSF Scorecard du dépôt.
import {
  to = github_repository.site
  id = var.repository
}

resource "github_repository" "site" {
  name         = var.repository
  description  = "🏠 Personal Website"
  homepage_url = "https://sylvain.dev"
  visibility   = "public"

  topics = ["blog", "eleventy-website", "hacktoberfest", "personal-website", "static-site"]

  has_issues      = true
  has_wiki        = false
  has_projects    = true
  has_discussions = false

  allow_merge_commit     = true
  allow_squash_merge     = true
  allow_rebase_merge     = true
  allow_auto_merge       = false
  delete_branch_on_merge = false

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

resource "github_repository_vulnerability_alerts" "site" {
  repository = github_repository.site.name
  enabled    = true
}

# Alertes oui, PR automatiques non : Renovate (renovate.json du dépôt) gère les
# montées de version, Dependabot en ouvrirait des doublons.
resource "github_repository_dependabot_security_updates" "site" {
  repository = github_repository.site.name
  enabled    = false

  depends_on = [github_repository_vulnerability_alerts.site]
}

# main : PR obligatoire (sans approbation, le dépôt n'a qu'un mainteneur) et
# checks verts, ni force-push ni suppression, propriétaire compris (pas de
# bypass, Scorecard le pénalise). Sveltia CMS est en editorial_workflow : il
# publie en fusionnant ses PR, que ce ruleset laisse passer une fois les
# checks verts.
resource "github_repository_ruleset" "site_main" {
  name        = "main"
  repository  = github_repository.site.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion         = true
    non_fast_forward = true

    pull_request {
      required_approving_review_count   = 0
      dismiss_stale_reviews_on_push     = false
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_review_thread_resolution = false
    }

    # Noms des jobs : CI (eleventy_build.yml), CodeQL, SonarCloud. Pas de
    # « branche à jour » obligatoire, pour ne pas bloquer les PR Renovate.
    required_status_checks {
      strict_required_status_checks_policy = false

      dynamic "required_check" {
        for_each = var.required_checks
        content {
          context = required_check.value
        }
      }
    }
  }
}

# Accès de l'app GitHub de Cloudflare au dépôt, comme pour tofu/ref.
# PUT /user/installations/{id}/repositories/{repo_id} : PAT classique avec le
# scope repo obligatoire (voir tofu/ref/README.md).
resource "github_app_installation_repository" "cloudflare" {
  count = var.cloudflare_github_installation_id == null ? 0 : 1

  installation_id = var.cloudflare_github_installation_id
  repository      = github_repository.site.name
}

# Build quotidien (articles programmés, date de construction) : le workflow
# daily-build du dépôt site appelle ce deploy hook.
resource "github_actions_secret" "pages_deploy_hook" {
  # Les valeurs de sops_file sont sensibles, interdites dans count : seule la
  # présence de la clé est utilisée ici, elle n'a rien de secret.
  count = nonsensitive(local.pages_deploy_hook == null) ? 0 : 1

  repository  = github_repository.site.name
  secret_name = "CLOUDFLARE_PAGES_DEPLOY_HOOK"
  value       = local.pages_deploy_hook
}

# Analyse SonarCloud du dépôt site (workflow sonarcloud.yml, organisation
# sylvainmetayer-github, projet sylvainmetayer_site). Le projet SonarCloud lui-même
# est créé à la main, voir README.md.
resource "github_actions_secret" "sonar_token" {
  count = nonsensitive(local.sonar_token == null) ? 0 : 1

  repository  = github_repository.site.name
  secret_name = "SONAR_TOKEN"
  value       = local.sonar_token
}

# Sans deploy hook, le workflow Daily Build du dépôt site échoue chaque matin
# (secret CLOUDFLARE_PAGES_DEPLOY_HOOK absent) : articles programmés jamais
# publiés, webmentions jamais rafraîchies. Le plan le signale (avertissement,
# pas d'erreur) tant que la clé manque dans secrets.sops.yaml.
check "daily_build_deploy_hook" {
  assert {
    condition     = nonsensitive(local.pages_deploy_hook != null)
    error_message = "SITE_PAGES_DEPLOY_HOOK absent de secrets.sops.yaml : le Daily Build du dépôt site échouera. Voir tofu/site/README.md, « Secrets du dépôt site »."
  }
}
