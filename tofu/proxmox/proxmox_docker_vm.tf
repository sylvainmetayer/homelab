resource "proxmox_virtual_environment_file" "vm" {
  content_type = "snippets"
  datastore_id = "local"
  node_name = var.proxmox_node

  source_raw {
    data = <<-EOF
    #cloud-config
    hostname: test-ubuntu
    timezone: America/Toronto
    users:
      - name: sylvain
        groups:
          - sudo
        shell: /bin/bash
        ssh_authorized_keys:
          - ${trimspace(file("${path.root}/../../key.pub"))}
        sudo: ALL=(ALL) NOPASSWD:ALL
    package_update: true
    packages:
      - qemu-guest-agent
      - net-tools
      - curl
    runcmd:
      - systemctl enable qemu-guest-agent
      - systemctl start qemu-guest-agent
      - echo "done" > /tmp/cloud-config.done
    EOF

    file_name = "user-data-cloud-config-vm.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "debian_base" {
  name      = var.proxmox_vm.name
  node_name = var.proxmox_node
  vm_id     = var.proxmox_vm.template_id + 1

  clone {
    vm_id = var.proxmox_vm.template_id
    full  = true
  }

  cpu {
    cores = var.proxmox_vm.cores
    type  = "host"
  }

  memory {
    dedicated = var.proxmox_vm.memory
  }

  disk {
    datastore_id = var.proxmox_vm.storage
    interface    = "scsi0"
    size         = var.proxmox_vm.disk_size
  }

  network_device {
    bridge = var.proxmox_vm.bridge
    model  = "virtio"
  }

  agent {
    enabled = true
  }

  initialization {
    datastore_id = var.proxmox_vm.storage

    user_account {
      username = "bob"
      keys     = [trimspace(file("${path.root}/../../key.pub"))]
    }

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  lifecycle {
    ignore_changes = [initialization]
  }

  tags = ["managed-by-opentofu", "homelab"]
}
