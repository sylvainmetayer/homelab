# Resource, target and monitors: local.websites (websites.tf).
#
# Homebox: home inventory (items, locations, receipts, warranties). Web
# interface behind the SSO, with no path opened around it. The one client
# outside a browser session, Sylvain's local MCP server (scripts/homebox-mcp),
# passes the wall with a Pangolin access token (below), then Homebox's own
# API key.
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

output "uptime_backup_homebox_url" {
  description = "HOMEBOX - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["homebox"]
  sensitive   = true
}

# Access token of the local MCP server (scripts/homebox-mcp): sent as the
# P-Access-Token-Id / P-Access-Token headers, on top of the Homebox API key.
# The resource stays behind the SSO wall and the geo-filter for everything
# else. One token per client, revoked alone. Read them with
# `tofu output -json homebox_client_access_tokens`.
resource "pangolin_resource_access_token" "homebox_clients" {
  for_each = toset(["claude-code"])

  resource_id = pangolin_resource.website["homebox"].id
  title       = "${pangolin_resource.website["homebox"].name} ${each.key}"
}

output "homebox_client_access_tokens" {
  description = "HOMEBOX - En-têtes Pangolin des clients (serveur MCP local)"
  value = {
    for client, token in pangolin_resource_access_token.homebox_clients : client => {
      "P-Access-Token-Id" = tostring(token.id)
      "P-Access-Token"    = token.token
    }
  }
  sensitive = true
}
