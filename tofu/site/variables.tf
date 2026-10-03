variable "github_owner" {
  description = "Compte GitHub propriétaire du dépôt"
  type        = string
  default     = "sylvainmetayer"
}

variable "repository" {
  description = "Nom du dépôt GitHub du site"
  type        = string
  default     = "site"
}

# Le nom du projet donne le sous-domaine <nom>.pages.dev : « site » serait
# trop générique (et sans doute déjà pris).
variable "project_name" {
  description = "Nom du projet Cloudflare Pages"
  type        = string
  default     = "sylvain-dev"
}

variable "domain_zone" {
  description = "Zone DNS (OVH) du domaine"
  type        = string
  default     = "sylvain.dev"
}

# Pages n'accepte un domaine apex que si la zone est chez Cloudflare : le site
# est servi sur www, l'apex est redirigé par Pangolin (voir README.md).
variable "subdomain" {
  description = "Sous-domaine servi par Cloudflare Pages"
  type        = string
  default     = "www"
}

# false tant que l'apex est encore servi par Netlify : passer à true une fois
# les anciens enregistrements de l'apex supprimés chez OVH (README.md, étape 4).
variable "apex_to_pangolin" {
  description = "Faire pointer l'apex de la zone vers Pangolin (redirection 301 vers www)"
  type        = bool
  default     = false
}

# ID de l'installation de l'app GitHub « Cloudflare Workers and Pages » sur le
# compte : https://github.com/settings/installations/<id>. null = installation
# en mode « All repositories » (rien à ajouter).
variable "cloudflare_github_installation_id" {
  description = "ID d'installation de l'app GitHub Cloudflare (mode « Only select repositories »)"
  type        = number
  default     = null
}
