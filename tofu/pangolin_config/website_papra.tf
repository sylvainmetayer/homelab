# Resource, target and monitors: local.websites (websites.tf).
#
# Papra: scanned documents with OCR, on trial as a lighter replacement of
# Paperless-ngx (paused, website_paperless.tf). Web interface only, behind
# the SSO, with no path opened around it: no share link and no mobile app
# yet (both would need path ACCEPTs, see local.path_bypasses in rules.tf).
locals {
  papra_website = {
    name      = "Papra"
    subdomain = "papra"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "papra"
    backup    = true

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Documents"
      description = "Documents numérisés, avec OCR (à l'essai)"
      icon        = "papra"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "papra"
      port    = 1221
      # Answers 200 without an account, and 500 when the SQLite database does
      # not answer: goes through the API, not only the static client (`/`
      # would).
      hc_path = "/api/health"
    }
  }
}

output "papra_access_token" {
  description = "PAPRA - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["papra"]
  sensitive   = true
}

output "uptime_backup_papra_url" {
  description = "PAPRA - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["papra"]
  sensitive   = true
}
