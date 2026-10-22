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
  # Certificat vérifié : Proxmox a un certificat Let's Encrypt pour
  # pve.sylvain.cloud (ACME DNS-01 OVH, configuré sur le nœud), résolu sur le
  # LAN ou par pve.internal (client Pangolin, tofu/pangolin_config).
  insecure = false
}
