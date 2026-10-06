# Resource, target and monitors: local.websites (websites.tf). No backup
# monitor.
locals {
  immich_swipe_website = {
    name      = "Immich Swipe"
    subdomain = "swipe-photos"
    domain_id = local.domain_ids["sylvain.cloud"]

    # Bound to Immich's role, not to one of its own.
    role = "immich"

    target = {
      site_id = pangolin_site.pi.id
      ip      = "immich-swipe"
      port    = 80
    }
  }
}

output "immich_swipe_access_token" {
  description = "IMMICH_SWIPE - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["immich_swipe"]
  sensitive   = true
}
