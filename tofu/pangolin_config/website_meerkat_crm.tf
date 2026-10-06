# Resource, target and monitors: local.websites (websites.tf).
locals {
  meerkat_crm_website = {
    name      = "Meerkat CRM"
    subdomain = "crm"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "meerkat-crm"
    backup    = true

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "meerkat-frontend"
      port    = 8080
    }
  }
}

# CardDAV for phone contact apps, which cannot go through the SSO wall.
# Opened worldwide through local.path_bypasses (rules.tf). Read off Meerkat CRM
# v1.7.0 (backend/routes/routes.go, backend/carddav/auth.go): `/carddav/*`
# behind HTTP Basic with the account's username or e-mail and its password,
# with per-account lockout and a rate limit; `/.well-known/carddav` answers a
# 301 to `/carddav/`. The frontend nginx proxies both to the backend. Enabled
# by CARDDAV_ENABLED in the role's env.
#
# Unlike Monica, this is the account password: keep it long.
locals {
  meerkat_crm_dav_paths = {
    "/carddav/*"           = 4
    "/.well-known/carddav" = 4
  }
}

output "meerkat_crm_access_token" {
  description = "MEERKAT_CRM - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["meerkat_crm"]
  sensitive   = true
}

output "uptime_backup_meerkat_crm_url" {
  description = "MEERKAT_CRM - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["meerkat_crm"]
  sensitive   = true
}
