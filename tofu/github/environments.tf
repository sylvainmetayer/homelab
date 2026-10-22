# Environnement sur lequel .github/workflows/path-bypass-review.yaml retient une
# PR qui monte la version d'une image dont local.path_bypasses ouvre des
# chemins sans SSO (tofu/pangolin_config/path_bypass_images.json). Le job
# attend qu'un relecteur clique « Review deployments » → « Approve and
# deploy », une fois les notes de version et les sources relues : rien n'est
# déployé, l'approbation fait seulement passer le check au vert.
#
# Les relecteurs obligatoires d'un environnement sont gratuits sur un dépôt
# public, ce qu'est homelab. Sans `tofu apply` de ce fichier, le premier job
# qui le cite crée l'environnement sans protection et passe sans attendre.
data "github_user" "owner" {
  username = var.github_owner
}

resource "github_repository_environment" "relecture_chemins_publics" {
  repository  = var.github_repository
  environment = "relecture-chemins-publics"

  # La PR est ouverte par Renovate : celui qui approuve n'a pas déclenché le
  # run. Le garder à false permet aussi d'approuver une montée poussée à la
  # main.
  prevent_self_review = false

  reviewers {
    users = [data.github_user.owner.id]
  }

  # Pas de deployment_branch_policy : le job tourne sur les branches de PR
  # (renovate/*), qu'une politique limitée aux branches protégées refuserait.
}

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
