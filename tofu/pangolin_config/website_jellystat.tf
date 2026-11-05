# Resource, target and monitors: local.websites (websites.tf).
#
# Jellystat: statistics of the NAS's Jellyfin, on the Docker VM (the VM reaches
# Jellyfin on the LAN, as Homepage's widget does). Behind the SSO wall and the
# country rules like every resource, then Jellystat's own login (the account
# its first-run wizard creates). No path opened, no access token.
locals {
  jellystat_website = {
    name      = "Jellystat"
    subdomain = "jellystat"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "jellystat"
    backup    = true

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Photos et médias"
      description = "Statistiques de lecture de Jellyfin"
      icon        = "jellystat"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "jellystat"
      port    = 3000
      # 200 without a session (its own healthcheck): {"state":0|1|2,...}.
      hc_path = "/auth/isconfigured"
    }
  }
}

output "uptime_backup_jellystat_url" {
  description = "JELLYSTAT - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["jellystat"]
  sensitive   = true
}
