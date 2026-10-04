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
  }
}

# GITHUB_TOKEN/GH_TOKEN, ex. export GITHUB_TOKEN="$(gh auth token)"
provider "github" {
  owner = var.github_owner
}

# CLOUDFLARE_API_TOKEN (Cloudflare Pages Edit + Account Analytics Read + Web
# Analytics Edit, voir README.md) : chargé par mise depuis secrets.sops.yaml.
provider "cloudflare" {}

# OVH_APPLICATION_KEY/SECRET, OVH_CONSUMER_KEY : chargés par mise depuis secrets.sops.yaml
provider "ovh" {
  endpoint = "ovh-eu"
}
