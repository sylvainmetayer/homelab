variable "proxmox_url" {
  description = "URL de l'API Proxmox (ex: https://proxmox.example.com:8006)"
  type        = string
}


variable "proxmox_node" {
  description = "Nom du noeud Proxmox"
  type        = string
  default     = "pve"
}

variable "proxmox_vm" {
  description = "Configuration de la VM Proxmox"
  type = object({
    name        = optional(string, "debian-base")
    template_id = optional(number, 9000)
    cores       = optional(number, 2)
    memory      = optional(number, 2048)
    disk_size   = optional(number, 20)
    storage     = optional(string, "local-lvm")
    bridge      = optional(string, "vmbr0")
  })
  default = {}
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
