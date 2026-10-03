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
}
