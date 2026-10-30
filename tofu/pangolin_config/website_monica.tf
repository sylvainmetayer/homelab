# Resource, target and monitors: local.websites (websites.tf).
locals {
  monica_website = {
    name      = "Monica CRM"
    subdomain = "crm"
    domain_id = local.domain_ids["sylvain.dev"]
    role      = "monica"
    backup    = true

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Contacts"
      description = "CRM personnel"
      icon        = "mdi-account-heart"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "monica_v4"
      port    = 80
    }
  }
}

# CardDAV/CalDAV for phone contact and calendar apps, which cannot go through
# the SSO wall. Opened worldwide through local.path_bypasses (rules.tf). Read
# off Monica v3.7.0: laravel-sabre on `/dav` (config/laravelsabre.php), behind
# HTTP Basic where the password is a Monica personal access token
# (AuthenticateWithTokenOnBasicAuth), not the account password. The two
# `.well-known` paths answer a 301 to `/dav/` (routes/web.php).
#
# Monica only serves `/dav` when DAV_ENABLED=true in its .env, templated by
# the monica_v4 role (false today: php_lockdown.tf also disables these paths).
locals {
  monica_dav_paths = {
    "/dav/*"               = 4
    "/.well-known/carddav" = 4
    "/.well-known/caldav"  = 4
  }
}

resource "uptimekuma_monitor_push" "cron_monica" {
  name = "Cron ${pangolin_resource.website["monica"].name}"

  # Not a backup: grouped with the healthchecks. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval = 60 * 15

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = local.alert_notification_ids
}

output "monica_access_token" {
  description = "MONICA - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["monica"]
  sensitive   = true
}

output "uptime_backup_monica_url" {
  description = "MONICA - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["monica"]
  sensitive   = true
}

output "uptime_cron_monica_url" {
  description = "MONICA - URL pour envoyer les heartbeats push du cron"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_monica.push_token}"
  sensitive   = true
}
