# Site de parrainage (11ty + Sveltia CMS), dépôt poussé à la main depuis
# ~/Documents/ref : pas d'auto_init, qui créerait un commit racine étranger.
# Le module commun est décrit dans tofu/modules/pages_site.
#
# Pas de vérification de la version de Node (celle de tofu/1y/node.tf) : le
# wrangler.toml du dépôt ref ne déclare pas de NODE_VERSION.
module "pages" {
  source = "../modules/pages_site"

  github_owner = var.github_owner
  repository   = var.repository
  domain_zone  = var.domain_zone
  subdomain    = var.subdomain

  description = "Mes codes et liens de parrainage - ${var.subdomain}.${var.domain_zone}"
  topics      = ["eleventy", "cloudflare-pages", "sveltia-cms"]
  auto_init   = false

  # PR Dependabot pour les failles connues (pas de Renovate sur ce dépôt).
  dependabot_security_updates = true

  cloudflare_github_installation_id = var.cloudflare_github_installation_id
  cloudflare_account_id             = local.cloudflare_account_id

  # Les bindings (dataset Analytics Engine EVENTS) et la date de compatibilité
  # vivent dans le wrangler.toml du dépôt, qui fait foi pour Pages.
  build_command   = "npm run build"
  destination_dir = "_site"
}

# Le jeton est recopié à la main dans le dépôt ref (README, étape 2). Si le site
# Web Analytics est recréé (changement d'hôte…), le plan le signale au lieu de
# laisser les pages vues se perdre sans bruit.
#
# Data source hors du bloc check : à l'intérieur, OpenTofu reporte toujours sa
# lecture à l'apply et le plan n'est jamais vide. var.repository plutôt que le
# nom du dépôt géré, pour qu'il soit lu au plan dans tous les cas.
data "github_repository_file" "site_json" {
  repository = var.repository
  file       = "src/_data/site.json"
  branch     = "main"
}

check "beacon_token" {
  assert {
    condition     = try(jsondecode(data.github_repository_file.site_json.content).cfBeaconToken, null) == module.pages.web_analytics_site.site_token
    error_message = "cfBeaconToken de src/_data/site.json (dépôt ref) ne correspond pas à `tofu output -raw web_analytics_token`."
  }
}
