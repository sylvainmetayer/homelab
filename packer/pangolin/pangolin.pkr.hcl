packer {
  required_plugins {
    hcloud = {
      source  = "github.com/hetznercloud/hcloud"
      version = ">= 1.6.0"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = ">= 1.1.0"
    }
  }
}

variable "image" {
  type        = string
  default     = "debian-13"
  description = "Base image for the snapshot"
}

variable "location" {
  type        = string
  default     = "nbg1"
  description = "Hetzner datacenter location"
}

variable "server_type" {
  type        = string
  default     = "cx23"
  description = "Server type for building the image"
}

source "hcloud" "pangolin" {
  image        = var.image
  location     = var.location
  server_type  = var.server_type
  server_name  = "packer-pangolin-build"
  snapshot_name = "pangolin-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  snapshot_labels = {
    app        = "pangolin"
    managed_by = "packer"
  }
  ssh_username = "root"
}

build {
  sources = ["source.hcloud.pangolin"]

  # Provision with Ansible
  provisioner "ansible" {
    playbook_file           = "${path.root}/ansible/site.yml"
    user                    = "root"
    galaxy_file             = "${path.root}/ansible/requirements.yml"
    galaxy_force_install    = true
    roles_path              = "${path.root}/../../ansible/galaxy_roles:${path.root}/../../ansible/roles"
    ansible_env_vars        = ["ANSIBLE_ROLES_PATH=${path.root}/../../ansible/galaxy_roles:${path.root}/../../ansible/roles"]
  }

  # Clean up for cloud-init re-run
  provisioner "shell" {
    inline = [
      "cloud-init clean --logs --machine-id --seed --configs all",
      "rm -rf /run/cloud-init/*",
      "rm -rf /var/lib/cloud/*",
      "rm -f /etc/ssh/ssh_host_*",
      "truncate -s 0 /etc/machine-id",
      "rm -f /var/lib/dbus/machine-id",
      "apt-get -y autopurge",
      "apt-get -y clean",
      "journalctl --flush",
      "journalctl --rotate --vacuum-time=0",
      "rm -rf /var/lib/apt/lists/*",
      "rm -rf /tmp/* /var/tmp/*",
      "find /var/log -type f -exec truncate --size 0 {} \\;",
      "find /var/log -type f -name '*.[1-9]' -delete",
      "find /var/log -type f -name '*.gz' -delete",
      "fstrim --all || true",
      "sync"
    ]
  }
}
