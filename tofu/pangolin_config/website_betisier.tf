# Resource, target and monitors: local.websites (websites.tf).
locals {
  betisier_website = {
    name      = "Betisier"
    subdomain = "betisier"
    domain_id = local.domain_ids["sylvain.dev"]

    # The only public resource without the SSO wall, so no role either: the
    # application is its own and only guard.
    sso    = false
    backup = true

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "betisier"
      port    = 80
    }
  }
}

output "betisier_access_token" {
  description = "BETISIER - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["betisier"]
  sensitive   = true
}

output "uptime_backup_betisier_url" {
  description = "BETISIER - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["betisier"]
  sensitive   = true
}
