# Le dépôt existe depuis longtemps et n'est pas géré ici (contrairement à
# tofu/ref) : on le lit seulement.
data "github_repository" "site" {
  full_name = "${var.github_owner}/${var.repository}"
}

# Accès de l'app GitHub de Cloudflare au dépôt, comme pour tofu/ref.
# PUT /user/installations/{id}/repositories/{repo_id} : PAT classique avec le
# scope repo obligatoire (voir tofu/ref/README.md).
resource "github_app_installation_repository" "cloudflare" {
  count = var.cloudflare_github_installation_id == null ? 0 : 1

  installation_id = var.cloudflare_github_installation_id
  repository      = data.github_repository.site.name
}

# Build quotidien (articles programmés, date de construction) : le workflow
# daily-build du dépôt site appelle ce deploy hook.
resource "github_actions_secret" "pages_deploy_hook" {
  # Les valeurs de sops_file sont sensibles, interdites dans count : seule la
  # présence de la clé est utilisée ici, elle n'a rien de secret.
  count = nonsensitive(local.pages_deploy_hook == null) ? 0 : 1

  repository      = data.github_repository.site.name
  secret_name     = "CLOUDFLARE_PAGES_DEPLOY_HOOK"
  plaintext_value = local.pages_deploy_hook
}

# Analyse SonarCloud du dépôt site (workflow sonarcloud.yml, organisation
# sylvainmetayer, projet sylvainmetayer_site). Le projet SonarCloud lui-même
# est créé à la main, voir README.md.
resource "github_actions_secret" "sonar_token" {
  count = nonsensitive(local.sonar_token == null) ? 0 : 1

  repository      = data.github_repository.site.name
  secret_name     = "SONAR_TOKEN"
  plaintext_value = local.sonar_token
}
