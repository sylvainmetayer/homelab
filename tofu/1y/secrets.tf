data "sops_file" "secrets" {
  source_file = "${path.root}/../../secrets.sops.yaml"
}

locals {
  # Jeton API Cloudflare (compte) : Cloudflare Pages Edit + Account Analytics Read
  # + Web Analytics Edit. Voir README.md.
  cloudflare_api_token  = data.sops_file.secrets.data["CLOUDFLARE_API_TOKEN"]
  cloudflare_account_id = data.sops_file.secrets.data["CLOUDFLARE_ACCOUNT_ID"]
}
