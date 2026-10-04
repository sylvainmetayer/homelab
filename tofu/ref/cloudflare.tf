locals {
  hostname = "${var.subdomain}.${var.domain_zone}"
}

# Prérequis : l'application GitHub « Cloudflare Workers and Pages » installée
# sur le compte et ayant accès au dépôt (github_app_installation_repository
# dans github.tf, ou mode « All repositories »), sinon la création échoue.
#
# Les bindings (dataset Analytics Engine EVENTS) et la date de compatibilité
# ne sont PAS ici : ils vivent dans wrangler.toml du dépôt, qui fait foi pour
# Pages dès qu'il déclare pages_build_output_dir.
resource "cloudflare_pages_project" "ref" {
  account_id        = var.cloudflare_account_id
  name              = var.repository
  production_branch = "main"

  source = {
    type = "github"
    config = {
      owner                          = var.github_owner
      repo_name                      = github_repository.ref.name
      production_deployments_enabled = true
      preview_deployment_setting     = "all"
      pr_comments_enabled            = true
    }
  }

  depends_on = [github_app_installation_repository.cloudflare]

  build_config = {
    build_command   = "npm run build"
    destination_dir = "_site"
  }
}

# Cloudflare valide le domaine dès sa création : sans le CNAME, ref.sylvain.dev
# résout encore par le joker vers Pangolin et le domaine reste en échec.
resource "cloudflare_pages_domain" "ref" {
  account_id   = var.cloudflare_account_id
  project_name = cloudflare_pages_project.ref.name
  name         = local.hostname

  depends_on = [ovh_domain_zone_record.ref]
}

# Pages vues. sylvain.dev n'est pas une zone Cloudflare : pas d'injection
# automatique, le site insère le beacon avec le jeton exporté en sortie
# (site.json → cfBeaconToken).
resource "cloudflare_web_analytics_site" "ref" {
  account_id   = var.cloudflare_account_id
  host         = local.hostname
  auto_install = false
}

# Le jeton est recopié à la main dans le dépôt ref (README, étape 2). Si le site
# Web Analytics est recréé (changement d'hôte…), le plan le signale au lieu de
# laisser les pages vues se perdre sans bruit.
check "beacon_token" {
  data "github_repository_file" "site_json" {
    repository = github_repository.ref.name
    file       = "src/_data/site.json"
    branch     = "main"
  }

  assert {
    condition     = try(jsondecode(data.github_repository_file.site_json.content).cfBeaconToken, null) == cloudflare_web_analytics_site.ref.site_token
    error_message = "cfBeaconToken de src/_data/site.json (dépôt ref) ne correspond pas à `tofu output -raw web_analytics_token`."
  }
}
