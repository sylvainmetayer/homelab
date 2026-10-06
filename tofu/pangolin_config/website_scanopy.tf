# Resource, target and monitors: local.websites (websites.tf).
locals {
  scanopy_website = {
    name      = "Scanopy"
    subdomain = "scan"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "scanopy"
    backup    = true

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "scanopy-server"
      port    = 60072
    }
  }
}

output "scanopy_access_token" {
  description = "SCANOPY - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["scanopy"]
  sensitive   = true
}

output "uptime_backup_scanopy_url" {
  description = "SCANOPY - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["scanopy"]
  sensitive   = true
}
