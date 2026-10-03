# Le dépôt 1y existe depuis 2020 (copie du modèle nhoizey/1y) : il n'est pas
# géré ici, seul l'accès de l'app GitHub de Cloudflare l'est.
#
# PUT /user/installations/{id}/repositories/{repo_id}, qui n'accepte qu'un PAT
# classique avec le scope repo (pas le jeton OAuth de `gh auth token`) : voir
# README.md.
resource "github_app_installation_repository" "cloudflare" {
  count = var.cloudflare_github_installation_id == null ? 0 : 1

  installation_id = var.cloudflare_github_installation_id
  repository      = var.repository
}
