locals {
  hostname = "${var.subdomain}.${var.domain_zone}"
}

# Prérequis : l'app GitHub « Cloudflare Workers and Pages » a accès au dépôt
# (github_app_installation_repository dans github.tf, ou mode « All repositories »).
#
# Pas de wrangler.toml dans le dépôt site : il ferait foi pour la configuration
# du projet et masquerait les variables d'environnement déclarées ici.
resource "cloudflare_pages_project" "site" {
  account_id        = local.cloudflare_account_id
  name              = var.project_name
  production_branch = "main"

  source = {
    type = "github"
    config = {
      owner                          = var.github_owner
      repo_name                      = data.github_repository.site.name
      production_branch              = "main"
      production_deployments_enabled = true
      preview_deployment_setting     = "all"
      pr_comments_enabled            = true
    }
  }

  depends_on = [github_app_installation_repository.cloudflare]

  build_config = {
    build_command   = "npm run production"
    destination_dir = "dist"
    root_dir        = ""
  }

  # Remplace les contextes de netlify.toml : les brouillons et la date de
  # publication ne sont filtrés qu'en production (src/posts/posts.11tydata.js).
  deployment_configs = {
    production = {
      env_vars = {
        ELEVENTY_ENV = {
          type  = "plain_text"
          value = "production"
        }
      }
    }
    preview = {
      env_vars = {
        ELEVENTY_ENV = {
          type  = "plain_text"
          value = "preview"
        }
      }
    }
  }
}

resource "cloudflare_pages_domain" "site" {
  account_id   = local.cloudflare_account_id
  project_name = cloudflare_pages_project.site.name
  name         = local.hostname
}

# Pages vues. sylvain.dev n'est pas une zone Cloudflare : pas d'injection
# automatique, le site insère le beacon avec le jeton exporté en sortie
# (src/_data/site.json → cfBeaconToken).
resource "cloudflare_web_analytics_site" "site" {
  account_id   = local.cloudflare_account_id
  host         = local.hostname
  auto_install = false
}
