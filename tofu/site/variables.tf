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

# ID de l'installation de l'app GitHub « Cloudflare Workers and Pages » sur le
# compte : https://github.com/settings/installations/<id>. null = installation
# en mode « All repositories » (rien à ajouter).
variable "cloudflare_github_installation_id" {
  description = "ID d'installation de l'app GitHub Cloudflare (mode « Only select repositories »)"
  type        = number
  default     = null
}

# Checks qui doivent être verts pour fusionner sur main (ruleset, github.tf) :
# jobs du workflow CI, analyses CodeQL et SonarCloud.
variable "required_checks" {
  description = "Contextes de checks requis par le ruleset de main"
  type        = list(string)
  default = [
    "build",
    "html",
    "accessibility",
    "analyze (javascript-typescript)",
    "analyze (actions)",
    "SonarCloud Code Analysis",
  ]
}

# Handle Bluesky @sylvain.dev : l'apex redirige vers www, la vérification par
# /.well-known/atproto-did ne suivrait pas la redirection. Un TXT _atproto le
# remplace (dns.tf). null = pas d'enregistrement. Le DID est public : le mettre
# en valeur par défaut, un -var oublié à l'apply suivant supprimerait le TXT.
variable "bluesky_did" {
  description = "DID du compte Bluesky (did:plc:…) à rattacher au domaine, ou null"
  type        = string
  default     = "did:plc:pbspgulrbrcxalhy6ienvxlo"

  validation {
    condition     = var.bluesky_did == null || can(regex("^did:(plc|web):[a-zA-Z0-9._:%-]+$", var.bluesky_did))
    error_message = "bluesky_did doit être un DID (did:plc:… ou did:web:…)."
  }
}
