output "pages_subdomain" {
  description = "Sous-domaine pages.dev du projet"
  value       = cloudflare_pages_project.r.subdomain
}
