# Resource, target and monitors: local.websites (websites.tf).
locals {
  wiki_website = {
    name      = "Wiki (Bookstack)"
    subdomain = "wiki"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "wiki"
    backup    = true

    # BookStack's root answers 302 to /login when signed out: monitoring "/"
    # cost two requests per probe (the redirect, followed). The login page
    # itself, a 200, is the one request. Pangolin serves its maintenance page
    # on any path, so the inverted keyword still sees an outage.
    monitor_path = "/login"

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      title       = "BookStack"
      group       = "Documents"
      description = "Wiki"
      icon        = "bookstack"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "bookstack"
      port    = 80
      hc_path = "/login"
    }
  }
}

output "wiki_access_token" {
  description = "WIKI - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["wiki"]
  sensitive   = true
}

output "uptime_backup_wiki_url" {
  description = "WIKI - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["wiki"]
  sensitive   = true
}
