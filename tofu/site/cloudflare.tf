locals {
  hostname = "${var.subdomain}.${var.domain_zone}"
}

# Prérequis : l'app GitHub « Cloudflare Workers and Pages » a accès au dépôt
# (github_app_installation_repository dans github.tf, ou mode « All repositories »).
#
# Le site déduit ELEVENTY_ENV de CF_PAGES_BRANCH (eleventy.config.js). Variables
# d'environnement, en production uniquement : WEBMENTION_IO_TOKEN et
# CF_ANALYTICS_* (locals.production_env_vars, plus bas).
resource "cloudflare_pages_project" "site" {
  account_id        = local.cloudflare_account_id
  name              = var.project_name
  production_branch = "main"

  source = {
    type = "github"
    config = {
      owner                          = var.github_owner
      repo_name                      = github_repository.site.name
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

  # Variables de production seulement (les previews n'ont aucun jeton). Sans
  # aucun jeton dans secrets.sops.yaml, deployment_configs reste non déclaré.
  deployment_configs = length(local.production_env_vars) == 0 ? null : {
    production = { env_vars = local.production_env_vars }
    preview    = {}
  }
}

locals {
  # Les valeurs de sops_file sont sensibles : seule la présence des clés décide
  # des variables déclarées.
  production_env_vars = merge(
    nonsensitive(local.webmention_io_token == null) ? {} : {
      WEBMENTION_IO_TOKEN = { type = "secret_text", value = local.webmention_io_token }
    },
    # Les plus lus de l'accueil : jeton lecture seule, compte et site Web Analytics
    nonsensitive(local.cf_analytics_token == null) ? {} : {
      CF_ANALYTICS_TOKEN    = { type = "secret_text", value = local.cf_analytics_token }
      CF_ACCOUNT_ID         = { type = "plain_text", value = local.cloudflare_account_id }
      CF_ANALYTICS_SITE_TAG = { type = "plain_text", value = cloudflare_web_analytics_site.site.site_tag }
    },
  )
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
