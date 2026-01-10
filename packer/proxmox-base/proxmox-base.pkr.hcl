packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.2.0"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = ">= 1.1.0"
    }
  }
}

variable "proxmox_api_token" {
  type = string
  #sensitive = true
  description = "Token API Proxmox complet (format: root@pam!tokenname=uuid)"
  default     = env("PROXMOX_TOKEN")
}

# Extraction automatique du username et du token
locals {
  # Split le token complet : "root@pam!tokenname=uuid" -> ["root@pam!tokenname", "uuid"]
  token_parts = split("=", var.proxmox_api_token)

  # Username avec le nom du token : "root@pam!tokenname"
  proxmox_username = local.token_parts[0]

  # Extraire juste le nom du token après le "!" : "root@pam!tokenname" -> "tokenname"
  token_name = length(split("!", local.token_parts[0])) > 1 ? split("!", local.token_parts[0])[1] : ""

  # Token au format attendu par Packer : "tokenname=uuid"
  proxmox_token = length(local.token_parts) > 1 ? "${local.token_parts[1]}" : ""

}

variable "proxmox_url" {
  type        = string
  description = "Proxmox API URL (e.g., https://proxmox.example.com:8006/api2/json)"
}

variable "proxmox_node" {
  type        = string
  description = "Proxmox node name"
}

variable "proxmox_storage" {
  type        = string
  default     = "local-lvm"
  description = "Storage pool for the VM disk"
}

variable "proxmox_iso_storage" {
  type        = string
  default     = "local"
  description = "Storage pool for ISO files"
}

variable "iso_file" {
  type        = string
  default     = "local:iso/debian-13.3.0-amd64-netinst.iso"
  description = "Path to the Debian cloud image"
}

variable "vm_id" {
  type        = number
  default     = 9000
  description = "VM ID for the template"
}

variable "vm_name" {
  type        = string
  default     = "debian-base"
  description = "Name for the VM template"
}

variable "vm_cores" {
  type        = number
  default     = 2
  description = "Number of CPU cores"
}

variable "vm_memory" {
  type        = number
  default     = 2048
  description = "Memory in MB"
}

variable "vm_disk_size" {
  type        = string
  default     = "20G"
  description = "Disk size"
}

variable "ssh_username" {
  type        = string
  default     = "debian"
  description = "SSH username for provisioning"
}

source "proxmox-clone" "debian-base" {
  proxmox_url              = var.proxmox_url
  username                 = local.proxmox_username
  token                    = local.proxmox_token
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  clone_vm             = var.vm_name
  vm_id                = var.vm_id
  vm_name              = "packer-${var.vm_name}-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  template_name        = "${var.vm_name}-template-${formatdate("YYYY-MM-DD", timestamp())}"
  template_description = "Debian base image with Docker and security hardening - Built by Packer on ${formatdate("YYYY-MM-DD", timestamp())}"

  cores  = var.vm_cores
  memory = var.vm_memory

  network_adapters {
    bridge = "vmbr0"
    model  = "virtio"
  }

  scsi_controller = "virtio-scsi-single"

  ssh_username = var.ssh_username
  ssh_timeout  = "20m"
}

source "proxmox-iso" "debian-base" {
  proxmox_url              = var.proxmox_url
  username                 = local.proxmox_username
  token                    = local.proxmox_token
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  vm_id                = var.vm_id
  vm_name              = "packer-${var.vm_name}-build"
  template_name        = "${var.vm_name}-template-${formatdate("YYYY-MM-DD", timestamp())}"
  template_description = "Debian base image with Docker and security hardening - Built by Packer on ${formatdate("YYYY-MM-DD", timestamp())}"

  boot_iso {
    iso_file         = var.iso_file
    iso_storage_pool = var.proxmox_iso_storage
    unmount          = true
  }

  os       = "l26"
  cores    = var.vm_cores
  memory   = var.vm_memory
  cpu_type = "host"

  scsi_controller = "virtio-scsi-single"

  disks {
    type         = "scsi"
    storage_pool = var.proxmox_storage
    disk_size    = var.vm_disk_size
    format       = "raw"
  }

  network_adapters {
    bridge = "vmbr0"
    model  = "virtio"
  }

  cloud_init              = true
  cloud_init_storage_pool = var.proxmox_storage

  ssh_username = var.ssh_username
  ssh_timeout  = "20m"

  boot_command = [
    "<esc><wait>",
    "auto url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg<enter>"
  ]

  http_directory = "${path.root}/http"
}

build {
  sources = ["source.proxmox-iso.debian-base"]

  # Provision with Ansible
  provisioner "ansible" {
    playbook_file        = "${path.root}/ansible/site.yml"
    user                 = var.ssh_username
    galaxy_file          = "${path.root}/ansible/requirements.yml"
    galaxy_force_install = true
    extra_arguments      = ["-e", "ansible_become=true"]
  }

  # Clean up for cloud-init re-run
  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
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
