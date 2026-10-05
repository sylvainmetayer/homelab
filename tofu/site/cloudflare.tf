locals {
  hostname = "${var.subdomain}.${var.domain_zone}"
}

# Prérequis : l'app GitHub « Cloudflare Workers and Pages » a accès au dépôt
# (github_app_installation_repository dans github.tf, ou mode « All repositories »).
#
# Le site déduit ELEVENTY_ENV de CF_PAGES_BRANCH (eleventy.config.js). Seule
# variable d'environnement : WEBMENTION_IO_TOKEN, en production uniquement.
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

  # Sans jeton dans secrets.sops.yaml, deployment_configs reste non déclaré,
  # comme avant.
  deployment_configs = nonsensitive(local.webmention_io_token == null) ? null : {
    production = {
      env_vars = {
        WEBMENTION_IO_TOKEN = {
          type  = "secret_text"
          value = local.webmention_io_token
        }
      }
    }
    preview = {}
  }
}

resource "cloudflare_pages_domain" "site" {
  account_id   = local.cloudflare_account_id
  project_name = cloudflare_pages_project.site.name
  name         = local.hostname
}

# Pages vues. sylvain.dev n'est pas une zone Cloudflare : pas d'injection
# automatique, le site insère le beacon avec le jeton exporté en sortie
# (src/_data/site.json → cfBeaconToken). Le site existant (jeton b127465e…,
# créé à la main pour l'apex) est importé avant le premier apply, voir
# README.md : même jeton, historique conservé, l'hôte passe sur www.
resource "cloudflare_web_analytics_site" "site" {
  account_id   = local.cloudflare_account_id
  host         = local.hostname
  auto_install = false
}
