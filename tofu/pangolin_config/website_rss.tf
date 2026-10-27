# Resource, target and monitors: local.websites (websites.tf).
locals {
  rss_website = {
    name      = "RSS"
    subdomain = "rss"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "rss"
    backup    = true

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "rss"
      port    = 80
    }
  }
}

# Read in the browser only, mobile included: no client API, so no path is
# opened around the SSO wall. The Google Reader and Fever APIs are also turned
# off in FreshRSS itself (api_enabled, ansible/roles/rss): reached through the
# SSO, they answer 503.

output "rss_access_token" {
  description = "RSS - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["rss"]
  sensitive   = true
}

output "uptime_backup_rss_url" {
  description = "RSS - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["rss"]
  sensitive   = true
}
