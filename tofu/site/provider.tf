terraform {
  required_version = ">= 1.0"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    ovh = {
      source  = "ovh/ovh"
      version = "< 3.0.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.3"
    }
  }
}

# GITHUB_TOKEN/GH_TOKEN, ex. export GITHUB_TOKEN="$(gh auth token)"
provider "github" {
  owner = var.github_owner
}

provider "cloudflare" {
  api_token = local.cloudflare_api_token
}

# OVH_APPLICATION_KEY/SECRET, OVH_CONSUMER_KEY : chargés par mise depuis secrets.sops.yaml
provider "ovh" {
  endpoint = "ovh-eu"
}
