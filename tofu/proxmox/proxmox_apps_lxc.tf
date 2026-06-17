locals {
  app_lxc_authorized_keys = [
    for key_file in sort(fileset("${path.root}/../../keys", "*.pub")) :
    trimspace(file("${path.root}/../../keys/${key_file}"))
  ]
}

resource "random_password" "app_lxc_password" {
  for_each = var.lxc_apps

  length      = 16
  special     = false
  min_lower   = 1
  min_numeric = 1
  min_upper   = 1
}

resource "proxmox_virtual_environment_container" "apps" {
  for_each = var.lxc_apps

  node_name = var.proxmox_node
  vm_id     = each.value.vm_id

  initialization {
    hostname = each.value.hostname

    ip_config {
      ipv4 {
        address = each.value.ipv4_address
        gateway = each.value.gateway
      }
    }

    user_account {
      keys     = local.app_lxc_authorized_keys
      password = random_password.app_lxc_password[each.key].result
    }
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.debian.id
    type             = "debian"
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = each.value.storage
    size         = each.value.disk_size
  }

  network_interface {
    name   = "eth0"
    bridge = each.value.bridge
  }

  unprivileged = true
  features {
    nesting = false
  }

  startup {
    order      = 4
    up_delay   = "60"
    down_delay = "60"
  }

  tags = distinct(concat(
    ["managed-by-opentofu", "homelab", "app", "role:${each.key}"],
    each.value.tags
  ))
}
