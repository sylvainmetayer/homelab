terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # >= 0.118 : le nom court proxmox_download_file (0.118, l'ancien
      # proxmox_virtual_environment_download_file est déprécié). backup.tf :
      # proxmox_backup_job (0.99), le nom court proxmox_storage_nfs (0.100),
      # comment (0.115) et notification_mode (0.116) du job. Et
      # reboot_after_update = false qui fait échouer un apply exigeant un
      # arrêt au lieu d'éteindre la VM (vérifié en 0.116.0 et 0.118.1) : à
      # relire à chaque montée de version.
      version = ">= 0.118.0, < 1.0.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
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
  # LAN seulement : ailleurs, le joker *.sylvain.cloud mène à Pangolin, et
  # pve.internal (client Pangolin) ne correspond ni à l'endpoint ni au
  # certificat.
  insecure = false
}
