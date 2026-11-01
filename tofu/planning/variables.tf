variable "github_owner" {
  description = "Compte GitHub propriétaire du dépôt"
  type        = string
  default     = "sylvainmetayer"
}

# Le dépôt est géré par tofu/github (repository_planning_equipes.tf) : ce
# module ne fait que le lire par son nom.
variable "repository" {
  description = "Nom du dépôt GitHub, et du projet Cloudflare Pages"
  type        = string
  default     = "planning-equipes"
}

# Dossier du site dans le dépôt : racine du projet Pages (là où Pages lit
# wrangler.toml) et seul chemin surveillé.
variable "site_dir" {
  description = "Dossier du site statique dans le dépôt"
  type        = string
  default     = "site"
}

variable "domain_zone" {
  description = "Zone DNS (OVH) du domaine personnalisé"
  type        = string
  default     = "sylvain.dev"
}

variable "subdomain" {
  description = "Sous-domaine du site dans la zone"
  type        = string
  default     = "planning"
}

# ID de l'installation de l'app GitHub « Cloudflare Workers and Pages » sur le
# compte : https://github.com/settings/installations/<id>. null = installation
# en mode « All repositories » (rien à ajouter). Même valeur que pour tofu/ref.
variable "cloudflare_github_installation_id" {
  description = "ID d'installation de l'app GitHub Cloudflare (mode « Only select repositories »)"
  type        = number
  default     = null
}
