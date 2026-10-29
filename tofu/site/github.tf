# main : PR obligatoire (sans approbation, le dépôt n'a qu'un mainteneur) et
# checks verts, ni force-push ni suppression, propriétaire compris (pas de
# bypass, Scorecard le pénalise). Sveltia CMS est en editorial_workflow : il
# publie en fusionnant ses PR, que ce ruleset laisse passer une fois les
# checks verts.
resource "github_repository_ruleset" "site_main" {
  name        = "main"
  repository  = module.pages.repository.name
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

# Build quotidien (articles programmés, date de construction) : le workflow
# daily-build du dépôt site appelle ce deploy hook.
resource "github_actions_secret" "pages_deploy_hook" {
  # Les valeurs de sops_file sont sensibles, interdites dans count : seule la
  # présence de la clé est utilisée ici, elle n'a rien de secret.
  count = nonsensitive(local.pages_deploy_hook == null) ? 0 : 1

  repository  = module.pages.repository.name
  secret_name = "CLOUDFLARE_PAGES_DEPLOY_HOOK"
  value       = local.pages_deploy_hook
}

# Analyse SonarCloud du dépôt site (workflow sonarcloud.yml, organisation
# sylvainmetayer-github, projet sylvainmetayer_site). Le projet SonarCloud lui-même
# est créé à la main, voir README.md.
resource "github_actions_secret" "sonar_token" {
  count = nonsensitive(local.sonar_token == null) ? 0 : 1

  repository  = module.pages.repository.name
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
