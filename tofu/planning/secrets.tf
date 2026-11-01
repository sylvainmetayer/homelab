data "sops_file" "secrets" {
  source_file = "${path.root}/../../secrets/secrets.sops.yaml"
}

locals {
  # Même jeton que tofu/ref et tofu/site (Cloudflare Pages Edit + Web Analytics
  # Edit) : voir tofu/ref/README.md, « Prérequis ».
  cloudflare_api_token  = data.sops_file.secrets.data["CLOUDFLARE_API_TOKEN"]
  cloudflare_account_id = data.sops_file.secrets.data["CLOUDFLARE_ACCOUNT_ID"]
}
