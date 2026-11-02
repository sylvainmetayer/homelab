# Doit être joué en premier avec pve.sylvain.cloud ou la connexion directe au PVE en local (IP en dur)
# avant de pouvoir utiliser l'alias interne via Pangolin

# Même renommage de type que debian_13 (proxmox_docker_vm.tf).
moved {
  from = proxmox_virtual_environment_download_file.debian
  to   = proxmox_download_file.debian
}

resource "proxmox_download_file" "debian" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = var.proxmox_node
  url          = "http://download.proxmox.com/images/system/debian-13-standard_13.1-2_amd64.tar.zst"
}

resource "random_password" "newt_password" {
  length      = 16
  special     = false
  min_lower   = 1
  min_numeric = 1
  min_upper   = 1
}

resource "proxmox_virtual_environment_container" "newt" {
  node_name = var.proxmox_node
  vm_id     = var.newt_lxc.vm_id


  initialization {
    hostname = var.newt_lxc.hostname

    ip_config {
      ipv4 {
        address = "192.168.1.200/24"
        gateway = "192.168.1.254"
      }
    }

    user_account {
      keys     = [trimspace(file("${path.root}/../../keys/perso.pub"))]
      password = random_password.newt_password.result
    }
  }

  operating_system {
    template_file_id = proxmox_download_file.debian.id
    type             = "debian"
  }

  cpu {
    cores = var.newt_lxc.cores
  }

  memory {
    dedicated = var.newt_lxc.memory
  }

  disk {
    datastore_id = var.newt_lxc.storage
    size         = var.newt_lxc.disk_size
  }

  network_interface {
    name   = "eth0"
    bridge = var.newt_lxc.bridge
  }

  unprivileged = true
  features {
    nesting = false
  }

  startup {
    order      = 3
    up_delay   = "60"
    down_delay = "60"
  }

  tags = ["managed-by-opentofu", "homelab", "newt"]
}
