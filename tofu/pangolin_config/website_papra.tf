# Resource, target and monitors: local.websites (websites.tf).
#
# Papra: scanned documents with OCR, on trial as a lighter replacement of
# Paperless-ngx (paused, website_paperless.tf). Behind the SSO, with no path
# opened around it: no share link (it would need a path ACCEPT, see
# local.path_bypasses in rules.tf).
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

# The official mobile app cannot go through the Pangolin SSO wall. As for
# Karakeep (website_karakeep.tf), it sends a Pangolin access token in the
# custom headers of its server screen (P-Access-Token-Id / P-Access-Token), on
# top of its Papra session: no path is opened, the whole API stays behind the
# SSO wall and the geo-filter.
#
# One token per client, so a lost phone is revoked without touching the others.
# Read them with `tofu output -json papra_client_access_tokens`.
resource "pangolin_resource_access_token" "papra_clients" {
  for_each = toset(["mobile"])

  resource_id = pangolin_resource.website["papra"].id
  title       = "${pangolin_resource.website["papra"].name} ${each.key}"
}

output "papra_client_access_tokens" {
  description = "PAPRA - En-têtes Pangolin des clients (app mobile)"
  value = {
    for client, token in pangolin_resource_access_token.papra_clients : client => {
      "P-Access-Token-Id" = tostring(token.id)
      "P-Access-Token"    = token.token
    }
  }
  sensitive = true
}

output "uptime_backup_papra_url" {
  description = "PAPRA - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["papra"]
  sensitive   = true
}
