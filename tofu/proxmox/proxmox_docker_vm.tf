# Téléchargement de l'image Debian 13 Trixie cloud
resource "proxmox_virtual_environment_download_file" "debian_13" {
  content_type        = "iso"
  datastore_id        = "local"
  file_name           = "debian-13-generic-amd64.img"
  node_name           = var.proxmox_node
  url                 = var.debian13_image_url
  checksum            = var.debian13_image_checksum
  checksum_algorithm  = var.debian13_image_checksum_algorithm
  overwrite           = true
  overwrite_unmanaged = true
}

# Fichier Cloud-Init vendor-config pour Debian 13
resource "proxmox_virtual_environment_file" "docker_vendor_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data = <<-EOF
    #cloud-config
    package_update: true
    packages:
      - qemu-guest-agent
    runcmd:
      - systemctl enable --now qemu-guest-agent
    EOF

    file_name = "docker-vendor-config.yaml"
  }
}

# Fichier Cloud-Init user-config pour Debian 13
resource "proxmox_virtual_environment_file" "docker_user_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data = <<-EOF
    #cloud-config
    hostname: ${var.docker_vm.hostname}
    users:
      - name: ${var.docker_vm.username}
        ssh_authorized_keys:
          - ${trimspace(file("${path.root}/../../key.pub"))}
        lock_passwd: false
        sudo: ['ALL=(ALL) NOPASSWD:ALL']
        shell: /bin/bash
    EOF

    file_name = "docker-user-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "docker" {
  depends_on = [
    proxmox_virtual_environment_file.docker_user_config,
    proxmox_virtual_environment_file.docker_vendor_config
  ]

  name        = var.docker_vm.name
  description = "Docker apps"
  tags        = ["tofu", "apps", "homelab"]
  node_name   = var.proxmox_node

  cpu {
    cores = var.docker_vm.cores
    type  = "host"
  }

  memory {
    dedicated = var.docker_vm.memory
    floating  = var.docker_vm.memory
  }

  disk {
    datastore_id = var.docker_vm.storage
    file_id      = proxmox_virtual_environment_download_file.debian_13.id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    ssd          = true
    size         = var.docker_vm.disk_size
  }

  network_device {
    bridge = var.docker_vm.bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    # Liaison des fichiers Cloud-Init
    user_data_file_id   = proxmox_virtual_environment_file.docker_user_config.id
    vendor_data_file_id = proxmox_virtual_environment_file.docker_vendor_config.id
  }
}

