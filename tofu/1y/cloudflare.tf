locals {
  hostname = "${var.subdomain}.${var.domain_zone}"

  # Première ligne `node = "…"` du fichier, c'est-à-dire celle de [tools].
  mise_node_version = try(regex("(?m)^node\\s*=\\s*[\"']([^\"']+)[\"']", data.github_repository_file.mise.content)[0], null)
}

# var.repository plutôt que github_repository.r.name : le fichier est lu au plan
# même quand le dépôt a des modifications en attente, la précondition aussi.
data "github_repository_file" "mise" {
  repository = var.repository
  file       = "mise.toml"
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
# Version de Node du build : Pages ne lit que .nvmrc/.node-version, pas le
# mise.toml du dépôt. Sans NODE_VERSION, il builde avec sa version par défaut
# (22.x en v3) ; la précondition bloque le plan si var.node_version et mise.toml
# (branche de production) divergent.
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

  deployment_configs = {
    production = {
      env_vars = {
        NODE_VERSION = { type = "plain_text", value = var.node_version }
      }
    }
    preview = {
      env_vars = {
        NODE_VERSION = { type = "plain_text", value = var.node_version }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = local.mise_node_version == var.node_version
      error_message = "var.node_version (${var.node_version}) ne correspond pas à la version de Node du mise.toml du dépôt ${var.repository}, branche ${var.production_branch} (${coalesce(local.mise_node_version, "introuvable")})."
    }
  }
}

resource "cloudflare_pages_domain" "r" {
  account_id   = local.cloudflare_account_id
  project_name = cloudflare_pages_project.r.name
  name         = local.hostname
}
