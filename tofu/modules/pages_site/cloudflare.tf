locals {
  hostname     = "${var.subdomain}.${var.domain_zone}"
  project_name = coalesce(var.project_name, var.repository)

  # Celle des deux variantes du projet Pages (plus bas) qui existe, réduite aux
  # attributs utiles : l'objet entier porte des attributs dépréciés
  # (deployments_enabled, usage_model), qui feraient avertir chaque plan.
  pages_project = [
    for p in(var.manage_deployment_configs ? cloudflare_pages_project.env_vars : cloudflare_pages_project.wrangler) : {
      account_id        = p.account_id
      name              = p.name
      subdomain         = p.subdomain
      production_branch = p.production_branch
      build_config      = p.build_config
      source = {
        type = p.source.type
        config = {
          owner             = p.source.config.owner
          repo_name         = p.source.config.repo_name
          production_branch = p.source.config.production_branch
        }
      }
      # Variables d'environnement seulement.
      env_vars = {
        production = try(p.deployment_configs.production.env_vars, null)
        preview    = try(p.deployment_configs.preview.env_vars, null)
      }
    }
  ][0]

  pages_source = {
    type = "github"
    config = {
      owner                          = var.github_owner
      repo_name                      = github_repository.this.name
      production_branch              = var.production_branch
      production_deployments_enabled = true
      preview_deployment_setting     = "all"
      pr_comments_enabled            = true
    }
  }

  build_config = {
    build_command   = var.build_command
    destination_dir = var.destination_dir
    root_dir        = ""
  }
}

# Prérequis : l'application GitHub « Cloudflare Workers and Pages » installée
# sur le compte et ayant accès au dépôt (github_app_installation_repository
# dans github.tf, ou mode « All repositories »), sinon la création échoue.
#
# Deux variantes, parce qu'un lifecycle ne se paramètre pas :
# - env_vars : deployment_configs géré ici (variables de production de
#   tofu/site, sans wrangler.toml) ;
# - wrangler : le wrangler.toml du dépôt fait foi pour deployment_configs dès
#   qu'il déclare pages_build_output_dir, et Cloudflare y renvoie
#   wrangler_config_hash (optionnel, non calculé côté provider) : sans
#   ignore_changes, chaque plan propose de l'effacer, diff permanent.
resource "cloudflare_pages_project" "env_vars" {
  count = var.manage_deployment_configs ? 1 : 0

  account_id        = var.cloudflare_account_id
  name              = local.project_name
  production_branch = var.production_branch

  source = local.pages_source

  depends_on = [github_app_installation_repository.cloudflare]

  build_config = local.build_config

  # Variables de production seulement (les previews n'ont aucun jeton). Sans
  # aucune variable, deployment_configs reste non déclaré.
  deployment_configs = length(var.production_env_vars) == 0 ? null : {
    production = { env_vars = var.production_env_vars }
    preview    = {}
  }
}

resource "cloudflare_pages_project" "wrangler" {
  count = var.manage_deployment_configs ? 0 : 1

  account_id        = var.cloudflare_account_id
  name              = local.project_name
  production_branch = var.production_branch

  source = local.pages_source

  depends_on = [github_app_installation_repository.cloudflare]

  build_config = local.build_config

  lifecycle {
    ignore_changes = [deployment_configs]
  }
}

# Cloudflare valide le domaine dès sa création : sans le CNAME, l'hôte résout
# encore par le joker vers Pangolin et le domaine reste en échec.
resource "cloudflare_pages_domain" "this" {
  account_id   = var.cloudflare_account_id
  project_name = local.pages_project.name
  name         = local.hostname

  depends_on = [ovh_domain_zone_record.cname]
}

# Pages vues. La zone n'est pas chez Cloudflare : pas d'injection automatique,
# le site insère le beacon avec le jeton exporté en sortie (site.json →
# cfBeaconToken).
resource "cloudflare_web_analytics_site" "this" {
  count = var.web_analytics ? 1 : 0

  account_id   = var.cloudflare_account_id
  host         = local.hostname
  auto_install = false
}
