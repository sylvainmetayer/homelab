variable "proxmox_url" {
  description = "URL de l'API Proxmox (ex: https://proxmox.example.com:8006)"
  type        = string
}


variable "proxmox_node" {
  description = "Nom du noeud Proxmox"
  type        = string
  default     = "pve"
}

variable "newt_lxc" {
  description = "Configuration de la VM Newt"
  type = object({
    vm_id       = optional(number, 200)
    hostname    = optional(string, "newt")
    template_id = optional(number, 9001)
    cores       = optional(number, 1)
    memory      = optional(number, 512)
    disk_size   = optional(number, 8)
    storage     = optional(string, "local-lvm")
    bridge      = optional(string, "vmbr0")
  })
  default = {}
}

variable "pangolin_url" {
  type = string
}

variable "debian13_image_url" {
  description = "URL de l'image Debian 13 Trixie"
  type        = string
  default     = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
}

variable "debian13_image_checksum_algorithm" {
  description = "Algorithme de somme de contrôle pour l'image Debian 13"
  type        = string
  default     = "sha512"
}

variable "debian13_image_checksum" {
  description = "Somme de contrôle SHA512 de l'image Debian 13"
  type        = string
  default     = ""
}

variable "docker_vm" {
  description = "Configuration de la VM Debian 13"
  type = object({
    name      = optional(string, "debian-13")
    vm_id     = optional(number, 300)
    hostname  = optional(string, "debian-13-vm")
    username  = optional(string, "sylvain")
    cores     = optional(number, 2)
    memory    = optional(number, 2048)
    disk_size = optional(number, 20)
    storage   = optional(string, "local-lvm")
    bridge    = optional(string, "vmbr0")
  })
  default = {}
}

variable "docker_vm_data_disks" {
  description = <<-EOT
    Disques par service nécessitant une BDD isolée du reste de la VM, backés
    par le storage Proxmox "iscsi-lvm" (LVM sur le LUN iSCSI unique du NAS,
    voir nas-storage-docker/homelab-storage-architecture.md). Ce storage est
    créé une fois, à la main, côté Proxmox (pvesm add iscsi / pvesm add lvm)
    — pas de ressource Tofu pour cette étape.
  EOT
  type = map(object({
    size_gb = number
  }))
  default = {}
}
