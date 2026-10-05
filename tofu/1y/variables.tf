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

# ID de l'installation de l'app GitHub Renovate sur le compte :
# https://github.com/settings/installations/<id>. null = installation en mode
# « All repositories », ou dépôt déjà sélectionné à la main (Renovate y a ouvert
# son onboarding en 2024, il y a donc déjà eu accès).
variable "renovate_github_installation_id" {
  description = "ID d'installation de l'app GitHub Renovate (mode « Only select repositories »)"
  type        = number
  default     = null
}

# À changer en même temps que [tools] node dans le mise.toml du dépôt (la
# précondition de cloudflare.tf le vérifie), une fois la PR mergée.
variable "node_version" {
  description = "Version de Node.js du build Pages (NODE_VERSION), identique au mise.toml du dépôt"
  type        = string
  default     = "26"
}
