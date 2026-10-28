# Resource, target and monitors: local.websites (websites.tf).
#
# Homebox: home inventory (items, locations, receipts, warranties). Web
# interface only, behind the SSO, with no path opened around it: nothing
# calls it from outside a browser session.
locals {
  homebox_website = {
    name      = "Homebox"
    subdomain = "homebox"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "homebox"
    backup    = true

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Vie perso"
      description = "Inventaire de la maison"
      icon        = "homebox"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "homebox"
      port    = 7745
      # The image's own HEALTHCHECK route: answers 200 without an account
      # and goes through the Go API, not only through the embedded static
      # files (`/` would).
      hc_path = "/api/v1/status"
    }
  }
}

output "homebox_access_token" {
  description = "HOMEBOX - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["homebox"]
  sensitive   = true
}

output "uptime_backup_homebox_url" {
  description = "HOMEBOX - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["homebox"]
  sensitive   = true
}
