# Resource, target and monitors: local.websites (websites.tf).
locals {
  rss_website = {
    name      = "RSS"
    subdomain = "rss"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "rss"
    backup    = true

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "rss"
      port    = 80
    }
  }
}

# Google Reader and Fever APIs for the mobile RSS readers, which cannot go
# through the SSO wall. Opened worldwide through local.path_bypasses
# (rules.tf). Read off FreshRSS 1.30.0 (p/api/greader.php, p/api/fever.php):
# both answer 503 unless the API is enabled, and authenticate with the user's
# API password (bcrypt for the Google Reader login, md5(user:password) as the
# Fever api_key). Neither rate-limits nor locks out, so that password has to
# be long and random.
#
# `/api/greader.php/*` also matches `/api/greader.php` itself, and covers its
# PATH_INFO routes (/accounts/ClientLogin, /reader/api/0/...). Not opened:
# `/i/` (the web UI, whose only lock would be FreshRSS's form login) and
# `/api/query.php` (shared user queries).
locals {
  rss_api_paths = {
    "/api/greader.php/*" = 4
    "/api/fever.php"     = 4
  }
}

output "rss_access_token" {
  description = "RSS - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["rss"]
  sensitive   = true
}

output "uptime_backup_rss_url" {
  description = "RSS - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["rss"]
  sensitive   = true
}
