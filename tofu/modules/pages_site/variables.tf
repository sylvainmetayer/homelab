# Site statique 11ty sur Cloudflare Pages, domaine personnalisé dans une zone
# OVH : dépôt GitHub et ses réglages, projet Pages + domaine, Web Analytics,
# CNAME OVH. Appelé par tofu/ref, tofu/site et tofu/1y ; ce qui n'appartient
# qu'à l'un d'eux (ruleset, secrets Actions, TXT _atproto, check du beacon,
# app Renovate) reste dans sa racine.
#
# Les attributs à null par défaut sont ceux qu'une racine ne déclarait pas
# avant ce module : les fixer pour toutes changerait les plans.

variable "github_owner" {
  description = "Compte GitHub propriétaire du dépôt"
  type        = string
}

variable "repository" {
  description = "Nom du dépôt GitHub"
  type        = string
}

# Le nom du projet donne le sous-domaine <nom>.pages.dev.
variable "project_name" {
  description = "Nom du projet Cloudflare Pages (null = nom du dépôt)"
  type        = string
  default     = null
}

variable "production_branch" {
  description = "Branche déployée en production (les autres ont des previews)"
  type        = string
  default     = "main"
}

variable "domain_zone" {
  description = "Zone DNS (OVH) du domaine personnalisé"
  type        = string
}

variable "subdomain" {
  description = "Sous-domaine servi par Cloudflare Pages dans la zone"
  type        = string
}

# --- Dépôt GitHub -----------------------------------------------------------

variable "description" {
  description = "Description du dépôt"
  type        = string
}

variable "homepage_url" {
  description = "Page d'accueil du dépôt (null = https://<sous-domaine>.<zone>)"
  type        = string
  default     = null
}

variable "topics" {
  description = "Sujets du dépôt"
  type        = list(string)
}

variable "auto_init" {
  description = "auto_init du dépôt (null = non déclaré)"
  type        = bool
  default     = null
}

variable "has_projects" {
  description = "Onglet Projects du dépôt"
  type        = bool
  default     = false
}

variable "allow_merge_commit" {
  description = "Fusion par merge commit autorisée"
  type        = bool
  default     = false
}

variable "allow_auto_merge" {
  description = "Auto-merge des PR (null = non déclaré)"
  type        = bool
  default     = null
}

variable "delete_branch_on_merge" {
  description = "Suppression des branches après fusion"
  type        = bool
  default     = true
}

# true : PR Dependabot pour les failles connues. false : alertes seulement,
# Renovate gère les montées de version.
variable "dependabot_security_updates" {
  description = "PR automatiques Dependabot pour les failles connues"
  type        = bool
  default     = false
}

variable "restrict_workflow_token" {
  description = "GITHUB_TOKEN des workflows en lecture seule par défaut"
  type        = bool
  default     = true
}

# Protection classique de la branche de production, sans PR obligatoire.
# false quand la racine protège la branche autrement (ruleset de tofu/site).
variable "protect_production_branch" {
  description = "Ni suppression ni force-push sur la branche de production, propriétaire compris"
  type        = bool
  default     = true
}

# ID de l'installation de l'app GitHub « Cloudflare Workers and Pages » sur le
# compte : https://github.com/settings/installations/<id>. null = installation
# en mode « All repositories » (rien à ajouter) ou pas encore faite.
variable "cloudflare_github_installation_id" {
  description = "ID d'installation de l'app GitHub Cloudflare (mode « Only select repositories »)"
  type        = number
  default     = null
}

# --- Cloudflare -------------------------------------------------------------

variable "cloudflare_account_id" {
  description = "Compte Cloudflare du projet Pages et du site Web Analytics"
  type        = string
}

# Sans défaut : chaque racine déclare son build (npm run build → _site pour
# ref et 1y, npm run production → dist pour site).
variable "build_command" {
  description = "Commande de build Pages"
  type        = string
}

variable "destination_dir" {
  description = "Dossier publié par le build"
  type        = string
}

# false : deployment_configs n'est pas géré ici, le wrangler.toml du dépôt fait
# foi (lifecycle ignore_changes, voir cloudflare.tf). true : variables
# d'environnement de production_env_vars, en production seulement.
variable "manage_deployment_configs" {
  description = "Gérer deployment_configs (variables d'environnement) au lieu de laisser wrangler.toml en décider"
  type        = bool
  default     = false
}

# Avec manage_deployment_configs. Vide : deployment_configs reste non déclaré.
# Les valeurs lues dans sops_file gardent leur marque sensible en traversant
# la variable.
variable "production_env_vars" {
  description = "Variables d'environnement du déploiement de production ({ NOM = { type, value } })"
  type = map(object({
    type  = string
    value = string
  }))
  default = {}
}

variable "web_analytics" {
  description = "Site Web Analytics (beacon inséré par le site, sans injection automatique)"
  type        = bool
  default     = true
}
