# Resource, target and monitors: local.websites (websites.tf).
#
# Speedtest Tracker: history of the home Internet line's speed (scheduled
# Ookla tests). Web interface only, behind the SSO, with no path opened
# around it: its API is not called from outside a browser session.
locals {
  speedtest_tracker_website = {
    name      = "Speedtest Tracker"
    subdomain = "speedtest"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "speedtest-tracker"
    backup    = true

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Administration"
      description = "Débit de la ligne Internet de la maison"
      icon        = "speedtest-tracker"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "speedtest-tracker"
      port    = 80
      # The API health route: answers 200 without an account and goes
      # through Laravel, not only through nginx (`/` redirects to the login
      # page).
      hc_path = "/api/healthcheck"
    }
  }
}

output "speedtest_tracker_access_token" {
  description = "SPEEDTEST TRACKER - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["speedtest_tracker"]
  sensitive   = true
}

output "uptime_backup_speedtest_tracker_url" {
  description = "SPEEDTEST TRACKER - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["speedtest_tracker"]
  sensitive   = true
}
