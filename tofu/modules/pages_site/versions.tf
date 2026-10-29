# Les blocs provider restent dans chaque racine (tofu/ref, tofu/site, tofu/1y),
# qui les passent implicitement à ce module.
terraform {
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
