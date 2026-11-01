# Donne accès au dépôt planning-equipes à l'app GitHub de Cloudflare, déjà
# installée sur le compte (tofu/ref) : utile seulement en mode « Only select
# repositories ». PUT /user/installations/{id}/repositories/{repo_id}, qui
# n'accepte qu'un PAT classique avec le scope repo (pas le jeton OAuth de
# `gh auth token`) : voir README.md.
#
# Le dépôt lui-même (visibilité, protection de main…) est dans tofu/github.
resource "github_app_installation_repository" "cloudflare" {
  count = var.cloudflare_github_installation_id == null ? 0 : 1

  installation_id = var.cloudflare_github_installation_id
  repository      = var.repository
}
