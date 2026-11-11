variable "github_owner" {
  description = "Compte GitHub propriétaire du dépôt"
  type        = string
  default     = "sylvainmetayer"
}

variable "repository" {
  description = "Nom du dépôt GitHub, et du projet Cloudflare Pages"
  type        = string
  default     = "ref"
}

variable "domain_zone" {
  description = "Zone DNS (OVH) du domaine personnalisé"
  type        = string
  default     = "sylvain.dev"
}

variable "subdomain" {
  description = "Sous-domaine du site dans la zone"
  type        = string
  default     = "ref"
}

# ID de l'installation de l'app GitHub « Cloudflare Workers and Pages » sur le
# compte : https://github.com/settings/installations/<id>. null = installation
# en mode « All repositories » (rien à ajouter) ou pas encore faite.
variable "cloudflare_github_installation_id" {
  description = "ID d'installation de l'app GitHub Cloudflare (mode « Only select repositories »)"
  type        = number
  default     = null
}

# Passphrase du chiffrement du state (encryption.tf), fournie par
# TF_VAR_state_encryption_passphrase : clé de secrets/secrets.sops.yaml, que
# mise charge dans l'environnement. Les tests en donnent une factice.
variable "state_encryption_passphrase" {
  description = "Passphrase PBKDF2 du chiffrement du state de ce module"
  type        = string
  sensitive   = true
}
