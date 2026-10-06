# Resource, target and monitors: local.websites (websites.tf).
locals {
  nextcloud_website = {
    name      = "nextcloud"
    subdomain = null
    domain_id = local.domain_ids["sylvain.cloud"]
    backup    = true

    # No SSO and so no role binding yet: with Betisier, the only public
    # resource without the Pangolin wall, pinned by the
    # `every_public_resource_applies_its_rules` test. The `nextcloud` slug of
    # roles.tf waits for the move behind the SSO.
    sso = false

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "nextcloud"
      port    = 80
      hc_path = "/login"
    }
  }
}

output "nextcloud_access_token" {
  description = "NEXTCLOUD - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["nextcloud"]
  sensitive   = true
}

output "uptime_backup_nextcloud_url" {
  description = "NEXTCLOUD - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["nextcloud"]
  sensitive   = true
}
