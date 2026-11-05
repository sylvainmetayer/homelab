# Resource, target and monitors: local.websites (websites.tf).
#
# Yamtrack: media tracker (films, series, anime, books, games), behind the SSO
# wall and the country rules like every resource, then Yamtrack's own login.
# No path opened, no access token.
#
# Its optional Jellyfin connection (watch events pushed by Jellyfin to
# /api/webhook/jellyfin/<token>) is NOT opened here: Jellyfin's server-to-server
# POST would hit the SSO wall. Opening it is a path bypass (local.path_bypasses,
# rules.tf, plus a path_bypass_images.json entry) to decide separately
# (ansible/roles/yamtrack/README.md).
locals {
  yamtrack_website = {
    name      = "Yamtrack"
    subdomain = "yamtrack"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "yamtrack"
    backup    = true

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Photos et médias"
      description = "Suivi de films, séries, animés, jeux et livres"
      icon        = "yamtrack"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "yamtrack"
      port    = 8000
      # Database, cache and Celery checks (the image's own healthcheck).
      hc_path = "/health/"
    }
  }
}

output "uptime_backup_yamtrack_url" {
  description = "YAMTRACK - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["yamtrack"]
  sensitive   = true
}
