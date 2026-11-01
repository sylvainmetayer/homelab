locals {
  hostname = "${var.subdomain}.${var.domain_zone}"

  # Pages qui portent le beacon Web Analytics, écrit en dur (pas de build pour
  # l'injecter) : la française et l'anglaise.
  beacon_pages = toset(["index.html", "en/index.html"])
}

# Vitrine statique de planning-equipes : dossier site/ du dépôt, sans build.
#
# Prérequis : l'application GitHub « Cloudflare Workers and Pages » installée
# sur le compte et ayant accès au dépôt (github_app_installation_repository
# dans github.tf, ou mode « All repositories »), sinon la création échoue.
#
# site/wrangler.toml fait foi pour le dossier publié (pages_build_output_dir =
# ".") et la date de compatibilité, dès qu'il déclare pages_build_output_dir.
resource "cloudflare_pages_project" "planning" {
  account_id        = local.cloudflare_account_id
  name              = var.repository
  production_branch = "main"

  source = {
    type = "github"
    config = {
      owner                          = var.github_owner
      repo_name                      = var.repository
      production_branch              = "main"
      production_deployments_enabled = true
      preview_deployment_setting     = "all"
      pr_comments_enabled            = true
      # Le dépôt est surtout l'application (Quarkus, Angular) : seul un commit
      # qui touche la vitrine déclenche un build, de production ou d'aperçu.
      # Optionnel et calculé : non déclaré, une dérive ne se verrait pas au plan.
      path_includes = ["${var.site_dir}/**"]
    }
  }

  depends_on = [github_app_installation_repository.cloudflare]

  # Pas de build : le dossier racine est publié tel quel.
  build_config = {
    build_command   = ""
    destination_dir = "."
    root_dir        = var.site_dir
  }

  # wrangler.toml fait foi pour deployment_configs, et Cloudflare y renvoie
  # wrangler_config_hash (optionnel, non calculé côté provider) : sans ce
  # ignore_changes, chaque plan propose de l'effacer, diff permanent (tofu/ref).
  lifecycle {
    ignore_changes = [deployment_configs]
  }
}

# Cloudflare valide le domaine dès sa création : sans le CNAME,
# planning.sylvain.dev résout encore par le joker vers Pangolin et le domaine
# reste en échec.
resource "cloudflare_pages_domain" "planning" {
  account_id   = local.cloudflare_account_id
  project_name = cloudflare_pages_project.planning.name
  name         = local.hostname

  depends_on = [ovh_domain_zone_record.planning]
}

# Pages vues. sylvain.dev n'est pas une zone Cloudflare : pas d'injection
# automatique, les deux pages chargent le beacon avec le jeton exporté en
# sortie (web_analytics_token), recopié à la main.
resource "cloudflare_web_analytics_site" "planning" {
  account_id   = local.cloudflare_account_id
  host         = local.hostname
  auto_install = false
}

# Le jeton est recopié à la main dans les deux pages (README.md, « Ordre des
# opérations »). Tant qu'il ne l'est pas, ou si le site Web Analytics est
# recréé (changement d'hôte…), le plan le signale au lieu de laisser les pages
# vues se perdre sans bruit.
#
# Data source hors du bloc check : à l'intérieur, OpenTofu reporte toujours sa
# lecture à l'apply et le plan n'est jamais vide.
data "github_repository_file" "beacon_pages" {
  for_each = local.beacon_pages

  repository = var.repository
  file       = "${var.site_dir}/${each.key}"
  branch     = "main"
}

check "beacon_token" {
  assert {
    condition = alltrue([
      for page in data.github_repository_file.beacon_pages :
      strcontains(try(page.content, ""), cloudflare_web_analytics_site.planning.site_token)
    ])
    error_message = "Le beacon de site/index.html ou site/en/index.html (dépôt planning-equipes, main) ne porte pas `tofu output -raw web_analytics_token`."
  }
}
