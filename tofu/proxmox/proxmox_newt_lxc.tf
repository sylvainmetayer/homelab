# Doit être joué en premier avec pve.sylvain.cloud ou la connexion directe au PVE en local (IP en dur)
# avant de pouvoir utiliser l'alias interne via Pangolin

resource "proxmox_virtual_environment_download_file" "debian" {
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

# FIXME Si ça arrive à s'intégrer avec un LXC container...
resource "proxmox_virtual_environment_file" "lxc" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data = <<-EOF
    #cloud-config
    hostname: test-ubuntu
    timezone: America/Toronto
    users:
      - default
      - name: ubuntu
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

    file_name = "user-data-cloud-config.yaml"
  }
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
      keys     = [trimspace(file("${path.root}/../../key.pub"))]
      password = random_password.newt_password.result
    }
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.debian.id
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


  # FIXME Quand ça marchera...
  # connection {
  #   type = "ssh"
  #   agent = false
  #   host = self.initialization[0].ip_config[0].ipv4[0].address
  #   user = "root"
  #   password = random_password.newt_password.result
  #   timeout = "2m"
  # }

  # provisioner "remote-exec" {
  #   inline = [
  #     "apt-get update",
  #     "apt-get install -y curl ca-certificates",
  #     "curl -L https://github.com/fosrl/newt/releases/download/1.8.1/newt_linux_amd64 -o /usr/local/bin/newt",
  #     "chmod +x /usr/local/bin/newt",
  #     "cat > /etc/systemd/system/newt.service <<EOF",
  #     "[Unit]",
  #     "Description=Newt Client for Pangolin",
  #     "After=network-online.target",
  #     "Wants=network-online.target",
  #     "[Service]",
  #     "Type=simple",
  #     nonsensitive("ExecStart=/usr/local/bin/newt --id ${local.newt_lxc_pangolin_id} --secret ${local.newt_lxc_pangolin_secret} --endpoint ${var.pangolin_url}"),
  #     "Restart=always",
  #     "RestartSec=10",
  #     "User=root",
  #     "[Install]",
  #     "WantedBy=multi-user.target",
  #     "EOF",
  #     "systemctl daemon-reload",
  #     "systemctl enable newt --now"
  #   ]
  # }
}
