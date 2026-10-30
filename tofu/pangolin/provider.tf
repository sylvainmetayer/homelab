terraform {
  required_version = ">= 1.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.58"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.3"
    }
    ovh = {
      source  = "ovh/ovh"
      version = "< 3.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "hcloud" {}
provider "ovh" {
  endpoint = "ovh-eu"
}
