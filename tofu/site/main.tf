# Le dépôt existe depuis 2017 : il a été importé, pas créé. Les réglages
# reprennent l'existant tel quel (description, méthodes de fusion…) ; seuls
# s'ajoutent le scan de secrets, les alertes Dependabot et le ruleset de main
# (github.tf), pour la note OpenSSF Scorecard du dépôt. Le module commun est
# décrit dans tofu/modules/pages_site.
#
# Pas de wrangler.toml dans le dépôt site : deployment_configs est géré ici
# (variables de production), et la vérification de la version de Node, propre
# à wrangler.toml, ne s'applique pas.
module "pages" {
  source = "../modules/pages_site"

  github_owner = var.github_owner
  repository   = var.repository
  project_name = var.project_name
  domain_zone  = var.domain_zone
  subdomain    = var.subdomain

  description  = "🏠 Personal Website"
  homepage_url = "https://sylvain.dev"
  topics       = ["blog", "eleventy-website", "personal-website", "static-site"]

  has_projects           = true
  allow_merge_commit     = true
  allow_auto_merge       = false
  delete_branch_on_merge = false

  # Alertes oui, PR automatiques non : Renovate (renovate.json du dépôt) gère
  # les montées de version, Dependabot en ouvrirait des doublons.
  dependabot_security_updates = false

  # main est protégée par le ruleset de github.tf, pas par une protection de
  # branche classique. Pas de restriction du jeton des workflows déclarée.
  protect_production_branch = false
  restrict_workflow_token   = false

  cloudflare_github_installation_id = var.cloudflare_github_installation_id
  cloudflare_account_id             = local.cloudflare_account_id

  # Le site déduit ELEVENTY_ENV de CF_PAGES_BRANCH (eleventy.config.js).
  build_command   = "npm run production"
  destination_dir = "dist"

  manage_deployment_configs = true
  production_env_vars       = local.production_env_vars
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
      CF_ANALYTICS_SITE_TAG = { type = "plain_text", value = module.pages.web_analytics_site.site_tag }
    },
  )
}
