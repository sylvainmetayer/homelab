data "sops_file" "secrets" {
  source_file = "${path.root}/../../secrets.sops.yaml"
}

locals {
  # Même jeton que tofu/ref : Cloudflare Pages Edit + Web Analytics Edit. Voir README.md.
  cloudflare_api_token  = data.sops_file.secrets.data["CLOUDFLARE_API_TOKEN"]
  cloudflare_account_id = data.sops_file.secrets.data["CLOUDFLARE_ACCOUNT_ID"]

  # URL du deploy hook Pages, créée à la main dans le dashboard (aucune API
  # dans le provider). Absente = pas de secret GitHub Actions (github.tf).
  pages_deploy_hook = try(data.sops_file.secrets.data["SITE_PAGES_DEPLOY_HOOK"], null)

  # Jeton API de webmention.io (https://webmention.io/settings), lu au build de
  # production pour afficher les réactions sous les articles. Absent = pas de
  # variable d'environnement, le site n'affiche simplement rien (cloudflare.tf).
  webmention_io_token = try(data.sops_file.secrets.data["SITE_WEBMENTION_IO_TOKEN"], null)

  # Jeton d'analyse SonarCloud (My Account → Security). Absent = pas de secret
  # GitHub Actions, le workflow sonarcloud du dépôt site saute l'analyse (github.tf).
  sonar_token = try(data.sops_file.secrets.data["SITE_SONAR_TOKEN"], null)
}
