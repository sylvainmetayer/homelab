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
