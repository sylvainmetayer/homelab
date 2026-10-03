variable "github_owner" {
  description = "Compte GitHub propriétaire du dépôt"
  type        = string
  default     = "sylvainmetayer"
}

variable "repository" {
  description = "Nom du dépôt GitHub, et du projet Cloudflare Pages"
  type        = string
  default     = "1y"
}

variable "production_branch" {
  description = "Branche déployée en production (les autres ont des previews)"
  type        = string
  default     = "master"
}

variable "domain_zone" {
  description = "Zone DNS (OVH) du domaine personnalisé"
  type        = string
  default     = "sylvain.dev"
}

variable "subdomain" {
  description = "Sous-domaine du site dans la zone"
  type        = string
  default     = "r"
}

# ID de l'installation de l'app GitHub « Cloudflare Workers and Pages » sur le
# compte : https://github.com/settings/installations/<id>. null = installation
# en mode « All repositories » (rien à ajouter). Même valeur que pour tofu/ref.
variable "cloudflare_github_installation_id" {
  description = "ID d'installation de l'app GitHub Cloudflare (mode « Only select repositories »)"
  type        = number
  default     = null
}
