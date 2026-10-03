locals {
  hostname = "${var.subdomain}.${var.domain_zone}"
}

# Prérequis : l'application GitHub « Cloudflare Workers and Pages » installée
# sur le compte et ayant accès au dépôt (github_app_installation_repository
# dans github.tf, ou mode « All repositories »), sinon la création échoue.
#
# La date de compatibilité et le dossier publié vivent dans le wrangler.toml du
# dépôt, qui fait foi pour Pages dès qu'il déclare pages_build_output_dir. Les
# redirections sont générées par 11ty dans _site/_redirects.
resource "cloudflare_pages_project" "r" {
  account_id        = local.cloudflare_account_id
  name              = var.repository
  production_branch = var.production_branch

  source = {
    type = "github"
    config = {
      owner                          = var.github_owner
      repo_name                      = var.repository
      production_branch              = var.production_branch
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

resource "cloudflare_pages_domain" "r" {
  account_id   = local.cloudflare_account_id
  project_name = cloudflare_pages_project.r.name
  name         = local.hostname
}
