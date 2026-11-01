output "pages_subdomain" {
  description = "Sous-domaine pages.dev du projet"
  value       = cloudflare_pages_project.planning.subdomain
}

output "web_analytics_site_tag" {
  description = "Identifiant du site Web Analytics (tableau de bord, API GraphQL)"
  value       = cloudflare_web_analytics_site.planning.site_tag
}

output "web_analytics_token" {
  description = "Jeton du beacon Web Analytics, à écrire dans site/index.html et site/en/index.html du dépôt planning-equipes"
  value       = cloudflare_web_analytics_site.planning.site_token
}
