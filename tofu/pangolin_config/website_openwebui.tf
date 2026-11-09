# Resource, target and monitors: local.websites (websites.tf).
#
# Open WebUI: chat interface for the household, its models served by Pangolin's
# AI Gateway (ai_gateway.tf, virtual key `openwebui`). Behind the SSO wall and
# the country rules like every resource, then Open WebUI's own login (Pocket
# ID, pocket_id.tf). No path opened, no access token: no mobile client, and
# its API keys stay off (ENABLE_API_KEYS, off by default).
locals {
  openwebui_website = {
    name      = "Open WebUI"
    subdomain = "openwebui"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "openwebui"
    backup    = true

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Divers"
      description = "Chat avec les modèles Claude, par la passerelle IA"
      icon        = "open-webui"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "openwebui"
      port    = 8080
      # Answers 200 {"status": true} without an account, and 503 while the
      # app is still starting (migrations).
      hc_path = "/health"
    }
  }
}

output "uptime_backup_openwebui_url" {
  description = "OPEN WEBUI - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["openwebui"]
  sensitive   = true
}
