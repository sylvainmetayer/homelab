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
      version = "~> 0.4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

# Connexion par utilisateur/mot de passe (le 2FA doit rester coupé). L'échec de
# connexion à l'instance PikaPods (breml/terraform-provider-uptimekuma#358, avec
# la 0.3.3) ne se produit plus en 0.4.x, même si l'issue reste ouverte en amont.
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

# Provider AWS configuré pour l'endpoint S3 compatible Hetzner
provider "aws" {
  region     = "eu-west-par"
  access_key = local.s3_access_key
  secret_key = local.s3_secret_key

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  skip_region_validation      = true

  endpoints {
    s3 = var.s3_endpoint
  }
}
