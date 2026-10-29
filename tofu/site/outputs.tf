output "pages_subdomain" {
  description = "Sous-domaine pages.dev du projet"
  value       = module.pages.pages_project.subdomain
}

output "web_analytics_token" {
  description = "Jeton du beacon Web Analytics, à mettre dans src/_data/site.json (cfBeaconToken) du dépôt site"
  value       = module.pages.web_analytics_site.site_token
}
