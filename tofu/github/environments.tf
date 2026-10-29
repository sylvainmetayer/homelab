# L'environnement relecture-chemins-publics (relecteur obligatoire, attendu
# par path-bypass-review.yaml) a été retiré le 2026-10-29 : une montée d'image
# de tofu/pangolin_config/path_bypass_images.json ne fusionne jamais seule, et
# la note que Renovate pose dans sa PR (dernière règle de renovate.json) dit
# quoi relire avant le merge à la main.

# Environnement du job de déploiement (deploy-docker-app.yaml) et du test de
# connexion OLM (ping.yaml) : la clé age de la CI, la clé SSH de déploiement
# et les identifiants OLM n'y sont lisibles que depuis main. Une branche de
# PR, même poussée par un collaborateur ou une action compromise, ne les voit
# pas. Sans relecteur : le déploiement au merge reste automatique.
resource "github_repository_environment" "production" {
  repository  = var.github_repository
  environment = "production"

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "production_main" {
  repository     = var.github_repository
  environment    = github_repository_environment.production.environment
  branch_pattern = "main"
}
