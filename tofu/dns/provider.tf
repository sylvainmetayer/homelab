terraform {
  required_version = ">= 1.0"

  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.3"
    }
    ovh = {
      source  = "ovh/ovh"
      version = "< 3.0.0"
    }
  }
}

provider "hcloud" {}
provider "ovh" {
  endpoint = "ovh-eu"
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
