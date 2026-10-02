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
  account_id        = local.cloudflare_account_id
  name              = var.repository
  production_branch = "main"

  source = {
    type = "github"
    config = {
      owner                          = var.github_owner
      repo_name                      = github_repository.ref.name
      production_branch              = "main"
      production_deployments_enabled = true
      preview_deployment_setting     = "all"
      pr_comments_enabled            = true
    }
  }

  depends_on = [github_app_installation_repository.cloudflare]

  build_config = {
    build_command   = "npm run build"
    destination_dir = "_site"
    root_dir        = ""
  }
}

resource "cloudflare_pages_domain" "ref" {
  account_id   = local.cloudflare_account_id
  project_name = cloudflare_pages_project.ref.name
  name         = local.hostname
}

# Pages vues. sylvain.dev n'est pas une zone Cloudflare : pas d'injection
# automatique, le site insère le beacon avec le jeton exporté en sortie
# (site.json → cfBeaconToken).
resource "cloudflare_web_analytics_site" "ref" {
  account_id   = local.cloudflare_account_id
  host         = local.hostname
  auto_install = false
}
