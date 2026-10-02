output "repository_ssh_url" {
  description = "Remote à ajouter dans ~/Documents/ref (git remote add origin …)"
  value       = github_repository.ref.ssh_clone_url
}

output "pages_subdomain" {
  description = "Sous-domaine pages.dev du projet"
  value       = cloudflare_pages_project.ref.subdomain
}

output "web_analytics_token" {
  description = "Jeton du beacon Web Analytics, à mettre dans src/_data/site.json (cfBeaconToken)"
  value       = cloudflare_web_analytics_site.ref.site_token
}
