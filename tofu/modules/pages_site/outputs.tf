# Les tests des racines (tofu/<site>/tests) ne voient les ressources du module
# que par ses sorties : d'où des objets plutôt que quelques attributs. Sans les
# attributs dépréciés, qui feraient avertir chaque plan. Conditionnelles
# plutôt que one() : une fonction marquerait l'objet entier sensible dès qu'un
# attribut l'est (account_id, variables d'environnement).

output "hostname" {
  description = "Hôte servi par Pages (<sous-domaine>.<zone>)"
  value       = local.hostname
}

# Sans l'attribut vulnerability_alerts, déprécié : l'objet entier ferait
# avertir chaque plan.
output "repository" {
  description = "Dépôt GitHub (attributs de github_repository)"
  value = {
    name                   = github_repository.this.name
    description            = github_repository.this.description
    homepage_url           = github_repository.this.homepage_url
    visibility             = github_repository.this.visibility
    topics                 = github_repository.this.topics
    auto_init              = github_repository.this.auto_init
    has_issues             = github_repository.this.has_issues
    has_projects           = github_repository.this.has_projects
    allow_merge_commit     = github_repository.this.allow_merge_commit
    allow_auto_merge       = github_repository.this.allow_auto_merge
    delete_branch_on_merge = github_repository.this.delete_branch_on_merge
    archive_on_destroy     = github_repository.this.archive_on_destroy
    security_and_analysis  = github_repository.this.security_and_analysis
    node_id                = github_repository.this.node_id
    ssh_clone_url          = github_repository.this.ssh_clone_url
  }
}

output "vulnerability_alerts" {
  description = "Alertes Dependabot du dépôt"
  value       = github_repository_vulnerability_alerts.this
}

output "dependabot_security_updates" {
  description = "PR Dependabot de sécurité du dépôt"
  value       = github_repository_dependabot_security_updates.this
}

output "workflow_permissions" {
  description = "Permissions par défaut du jeton des workflows (null sans restrict_workflow_token)"
  value       = var.restrict_workflow_token ? github_workflow_repository_permissions.this[0] : null
}

output "branch_protection" {
  description = "Protection de la branche de production (null sans protect_production_branch)"
  value       = var.protect_production_branch ? github_branch_protection.production[0] : null
}

output "cloudflare_app_installation" {
  description = "Accès de l'app GitHub Cloudflare au dépôt (liste vide sans ID d'installation)"
  value       = github_app_installation_repository.cloudflare
}

output "pages_project" {
  description = "Projet Cloudflare Pages (attributs utiles de cloudflare_pages_project)"
  value       = local.pages_project
}

output "pages_domain" {
  description = "Domaine personnalisé du projet Pages"
  value       = cloudflare_pages_domain.this
}

output "web_analytics_site" {
  description = "Site Web Analytics (null sans web_analytics)"
  value       = var.web_analytics ? cloudflare_web_analytics_site.this[0] : null
}

output "cname_record" {
  description = "CNAME OVH vers <projet>.pages.dev"
  value       = ovh_domain_zone_record.cname
}
