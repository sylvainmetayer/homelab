variable "vm_name" {
  description = "Nom de la VM"
  type        = string
}

variable "server_type" {
  description = "Type de serveur Hetzner (ex: cx11, cpx11, cx21)"
  type        = string
}

variable "image" {
  description = "Image du système d'exploitation"
  type        = string
  default     = "debian-13"
}

variable "location" {
  description = "Localisation du serveur (ex: nbg1, fsn1, hel1)"
  type        = string
  default     = "nbg1"
}

variable "ssh_key_name" {
  description = "Nom de la clé SSH"
  type        = string
}

variable "ssh_allowed_ips" {
  description = "IPs autorisées pour l'accès SSH"
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

variable "labels" {
  description = "Labels pour la VM"
  type        = map(string)
  default = {
    environment = "homelab"
    managed_by  = "opentofu"
  }
}

variable "user_data" {
  description = "Script d'initialisation cloud-init (optionnel)"
  type        = string
  default     = ""
}
