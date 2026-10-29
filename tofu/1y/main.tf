# Le dépôt 1y existe depuis 2020 (copie du modèle nhoizey/1y) : il a été
# importé, pas créé, et ses réglages alignés sur tofu/ref. Le module commun est
# décrit dans tofu/modules/pages_site.
#
# Pas de Web Analytics : les redirections de _redirects sont servies en
# bordure, aucune page ne chargerait le beacon.
module "pages" {
  source = "../modules/pages_site"

  github_owner      = var.github_owner
  repository        = var.repository
  production_branch = var.production_branch
  domain_zone       = var.domain_zone
  subdomain         = var.subdomain

  description = "Gestionnaire d'URL courtes - ${var.subdomain}.${var.domain_zone}"
  topics      = ["eleventy", "cloudflare-pages", "url-shortener"]

  # Alertes oui, PR automatiques non : Renovate (renovate.json du dépôt) gère
  # les montées de version, Dependabot en ouvrirait des doublons.
  dependabot_security_updates = false

  cloudflare_github_installation_id = var.cloudflare_github_installation_id
  cloudflare_account_id             = local.cloudflare_account_id

  # La date de compatibilité et le dossier publié vivent dans le wrangler.toml
  # du dépôt. Les redirections sont générées par 11ty dans _site/_redirects.
  build_command   = "npm run build"
  destination_dir = "_site"

  web_analytics = false
}

# Même mécanique que l'app Cloudflare (tofu/modules/pages_site/github.tf) : PAT
# classique avec le scope repo, voir README.md.
resource "github_app_installation_repository" "renovate" {
  count = var.renovate_github_installation_id == null ? 0 : 1

  installation_id = var.renovate_github_installation_id
  repository      = module.pages.repository.name
}
