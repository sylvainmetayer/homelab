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
      version = "~> 0.3.0"
    }
  }
}

# Wait for https://github.com/breml/terraform-provider-uptimekuma/issues/358 to be resolved.
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
  region     = "nbg1"
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
