locals {
  hostname = "${var.subdomain}.${var.domain_zone}"

  # Première ligne `node = "…"` du fichier, c'est-à-dire celle de [tools].
  mise_node_version = try(regex("(?m)^node\\s*=\\s*[\"']([^\"']+)[\"']", data.github_repository_file.mise.content)[0], null)
  # [vars] NODE_VERSION, la seule version que le build Pages lit.
  wrangler_node_version = try(regex("(?m)^NODE_VERSION\\s*=\\s*[\"']([^\"']+)[\"']", data.github_repository_file.wrangler.content)[0], null)
}

# var.repository plutôt que github_repository.r.name : les fichiers sont lus au
# plan même quand le dépôt a des modifications en attente, la précondition aussi.
data "github_repository_file" "mise" {
  repository = var.repository
  file       = "mise.toml"
  branch     = var.production_branch
}

data "github_repository_file" "wrangler" {
  repository = var.repository
  file       = "wrangler.toml"
  branch     = var.production_branch
}

# Prérequis : l'application GitHub « Cloudflare Workers and Pages » installée
# sur le compte et ayant accès au dépôt (github_app_installation_repository
# dans github.tf, ou mode « All repositories »), sinon la création échoue.
#
# La date de compatibilité et le dossier publié vivent dans le wrangler.toml du
# dépôt, qui fait foi pour Pages dès qu'il déclare pages_build_output_dir. Les
# redirections sont générées par 11ty dans _site/_redirects.
#
# Version de Node du build : Pages ne lit ni mise.toml ni, avec un wrangler.toml,
# les variables du dashboard (deployment_configs.env_vars est ignoré au build).
# Elle vient donc du [vars] NODE_VERSION de wrangler.toml ; la précondition
# bloque le plan s'il diverge de mise.toml (branche de production).
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


  lifecycle {
    precondition {
      condition     = local.mise_node_version != null && local.wrangler_node_version == local.mise_node_version
      error_message = "Dépôt ${var.repository}, branche ${var.production_branch} : NODE_VERSION de wrangler.toml (${coalesce(local.wrangler_node_version, "introuvable")}) ne correspond pas à [tools] node de mise.toml (${coalesce(local.mise_node_version, "introuvable")}). Le build Pages n'utilise que wrangler.toml."
    }
  }
}

resource "cloudflare_pages_domain" "r" {
  account_id   = local.cloudflare_account_id
  project_name = cloudflare_pages_project.r.name
  name         = local.hostname
}
