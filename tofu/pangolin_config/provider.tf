terraform {
  required_version = ">= 1.0"

  required_providers {
    pangolin = {
      source  = "stackopshq/pangolin"
      version = "~> 1.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.3"
    }
    uptimekuma = {
      source  = "breml/uptimekuma"
      version = "~> 0.5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

# Connexion par utilisateur/mot de passe (le 2FA doit rester coupé). L'échec de
# connexion à l'instance PikaPods (breml/terraform-provider-uptimekuma#358, avec
# la 0.3.3) ne se produit plus depuis la 0.4.x, même si l'issue reste ouverte en
# amont. La 0.5.0 lit et écrit l'instance sans écart (plan du 01/11/2026), sauf
# le jeton du canal ntfy, que la 0.4.0 n'envoyait pas (website_ntfy.tf).
provider "uptimekuma" {
  endpoint = local.uptimekuma_endpoint
  username = local.uptimekuma_username
  password = local.uptimekuma_password
}

provider "pangolin" {
  url     = local.pangolin_url
  api_key = local.pangolin_api_key
  org_id  = local.pangolin_org_id
}
