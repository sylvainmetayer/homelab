# Resource, target and monitors: local.websites (websites.tf).
locals {
  paperless_website = {
    name      = "Paperless-ngx"
    subdomain = "papiers"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "paperless"
    backup    = true

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "paperless"
      port    = 8000
    }
  }
}

# Share links (document > Share > link), opened worldwide without SSO through
# local.path_bypasses (rules.tf). Read off Paperless-ngx v3.2.1
# (src/paperless/urls.py, src/documents/views.py SharedLinkView):
# `/share/<slug>` answers the file itself (inline PDF/original, or a ZIP for a
# share-link bundle), no HTML page and no static file. The slug is 50 random
# alphanumerics, and the view checks expiry itself.
#
# An expired or unknown slug redirects to /accounts/login/, which stays behind
# the SSO wall: the visitor gets Pangolin's login rather than Paperless's
# "link expired" notice. Cosmetic, and opening the login page would be worse.
locals {
  paperless_share_paths = {
    "/share/*" = 4
  }
}

output "paperless_access_token" {
  description = "PAPERLESS - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["paperless"]
  sensitive   = true
}

output "uptime_backup_paperless_url" {
  description = "PAPERLESS - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["paperless"]
  sensitive   = true
}
