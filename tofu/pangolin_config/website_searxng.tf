# Resource, target and monitors: local.websites (websites.tf).
locals {
  searxng_website = {
    name      = "SearXNG"
    subdomain = "search"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "searxng"
    backup    = true

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "searxng"
      port    = 8080
    }
  }
}

output "searxng_access_token" {
  description = "SEARXNG - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["searxng"]
  sensitive   = true
}

output "uptime_backup_searxng_url" {
  description = "SEARXNG - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["searxng"]
  sensitive   = true
}
