terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "<1.0.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.3"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_url
  api_token = local.proxmox_api_token
  ssh {
    agent    = true
    username = "root"
  }
  insecure = true
}
