# Resource, target and monitors: local.websites (websites.tf).
locals {
  wiki_website = {
    name      = "Wiki (Bookstack)"
    subdomain = "wiki"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "wiki"
    backup    = true

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "bookstack"
      port    = 80
      hc_path = "/login"
    }
  }
}

output "wiki_access_token" {
  description = "WIKI - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["wiki"]
  sensitive   = true
}

output "uptime_backup_wiki_url" {
  description = "WIKI - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["wiki"]
  sensitive   = true
}
