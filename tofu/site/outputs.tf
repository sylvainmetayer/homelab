output "pages_subdomain" {
  description = "Sous-domaine pages.dev du projet"
  value       = cloudflare_pages_project.site.subdomain
}

output "web_analytics_token" {
  description = "Jeton du beacon Web Analytics, à mettre dans src/_data/site.json (cfBeaconToken) du dépôt site"
  value       = cloudflare_web_analytics_site.site.site_token
}
