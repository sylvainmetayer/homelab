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
          - ${trimspace(file("${path.root}/../../keys/perso.pub"))}
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

  # Jamais de redémarrage par le provider : un changement qui exige un arrêt
  # (port série, type de CPU…) est écrit dans la config Proxmox, en attente,
  # avec un avertissement « Please reboot the VM manually », et s'applique au
  # prochain démarrage à froid de la VM (`qm shutdown 100 --timeout 300 && qm
  # start 100`, ou le prochain reboot de l'hôte ; un reboot dans la VM ne suffit
  # pas). Le plan suivant est vide : seul `qm pending 100` montre ce qui attend.
  # Déplacer un disque, ou le redimensionner dans le même apply qu'un
  # changement en attente, fait échouer l'apply au lieu d'éteindre la VM (un
  # redimensionnement seul passe à chaud). Ne couvre pas un remplacement
  # (ForceNew, ex. les snippets cloud-init) : lire chaque plan. Défaut du
  # provider : true, qui éteint et rallume toutes les applis sans prévenir.
  reboot_after_update = false

  cpu {
    cores = var.docker_vm.cores
    type  = "host"
  }

  memory {
    dedicated = var.docker_vm.memory
    # Ballooning désactivé : les mem_limit des composes sont calibrées sur une
    # RAM fixe, un ballon pourrait faire descendre le dispo sous var.docker_vm.memory.
    floating = 0
  }

  disk {
    datastore_id = var.docker_vm.storage
    file_id      = proxmox_virtual_environment_download_file.debian_13.id
    interface    = "virtio0"
    iothread     = true
    # Sur le SSD M.2 SATA de l'hôte. Pas d'émulation SSD sur virtio-blk (la VM
    # voit rotational = 1, sans conséquence) ; le TRIM passe par discard + le
    # fstrim.timer hebdomadaire de la VM.
    discard = "on"
    ssd     = false
    size    = var.docker_vm.disk_size
  }

  lifecycle {
    ignore_changes = [
      disk[0].file_id
    ]
  }

  network_device {
    bridge = var.docker_vm.bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  # serial0 : l'image cloud Debian démarre avec console=ttyS0, et sans port
  # série serial-getty@ttyS0 échouait toutes les ~20 s (agetty « failed to get
  # terminal attributes: Input/output error », ~27 000 fois par semaine en
  # priorité err). Avec lui, la console xterm.js de Proxmox (et `qm terminal
  # 100`) ouvre un vrai login, les messages du noyau compris. L'écran VGA par
  # défaut reste : la console noVNC marche toujours. Ajouté à une VM qui
  # tourne, il n'est pris qu'à son prochain arrêt complet (voir
  # reboot_after_update).
  serial_device {
    device = "socket"
  }

  agent {
    enabled = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.1.216/24"
        gateway = "192.168.1.254"
      }
    }

    # Les DNS que donnait le DHCP de la box : sans eux, une IP fixe ne reçoit
    # que ceux de l'hôte Proxmox.
    dns {
      servers = ["192.168.1.254", "9.9.9.9", "1.1.1.1"]
    }

    # Liaison des fichiers Cloud-Init
    user_data_file_id   = proxmox_virtual_environment_file.docker_user_config.id
    vendor_data_file_id = proxmox_virtual_environment_file.docker_vendor_config.id
  }
}

