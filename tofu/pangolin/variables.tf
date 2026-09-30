variable "vm_name" {
  description = "Nom de la VM"
  type        = string
}

variable "server_type" {
  description = "Type de serveur Hetzner (ex: cx11, cpx11, cx21)"
  type        = string
}

variable "image" {
  description = "Image du système d'exploitation ou ID du snapshot Packer"
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

variable "labels" {
  description = "Labels pour la VM"
  type        = map(string)
  default = {
    environment = "homelab"
    managed_by  = "opentofu"
  }
}

variable "pangolin_config" {
  description = "Configuration Pangolin (config.yml)"
  type = object({
    dashboard_url = string
    base_domain   = string
    log_level     = optional(string, "info")
  })
}

variable "s3_bucket_name" {
  description = "Nom du bucket S3 Hetzner"
  type        = string
}

variable "s3_versioning_enabled" {
  description = "Activer le versioning sur le bucket S3"
  type        = bool
  default     = false
}

variable "s3_endpoint" {
  description = "Endpoint S3 Hetzner"
  type        = string
  default     = "https://s3.eu-west-par.io.cloud.ovh.net"
}

variable "flip_server" {
  description = "Serveur Flip Planning, sans IP publique (réseau privé uniquement)"
  type = object({
    name        = optional(string, "flip")
    server_type = optional(string, "cx23")
    image       = optional(string, "debian-13")
    # Doit rester dans hcloud_network_subnet.main (10.0.1.0/24), et en phase
    # avec l'ansible_host de flip dans .github/workflows/deploy-docker-app.yaml.
    private_ip = optional(string, "10.0.1.10")
  })
  default = {}
}
