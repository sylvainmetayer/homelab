resource "pangolin_resource" "monica" {
  name        = "Monica CRM"
  subdomain   = "crm"
  domain_id   = local.domain_ids["sylvain.dev"]
  protocol    = "tcp"
  sso         = true
  apply_rules = true

  # Optional+computed: pinned so a plan can disagree with the API. See
  # resource_defaults.tf.
  mode                    = local.resource_pins.mode
  ssl                     = local.resource_pins.ssl
  enabled                 = local.resource_pins.enabled
  block_access            = local.resource_pins.block_access
  email_whitelist_enabled = local.resource_pins.email_whitelist_enabled
  sticky_session          = local.resource_pins.sticky_session

  # Maintenance screen served automatically while no target is healthy.
  # See maintenance.tf.
  maintenance_mode_enabled = local.maintenance.enabled
  maintenance_mode_type    = local.maintenance.type
  maintenance_title        = local.maintenance.title
  maintenance_message      = local.maintenance.message
}

resource "pangolin_resource_role" "monica" {
  resource_id = pangolin_resource.monica.id
  role_id     = pangolin_role.apps["monica"].id
}

# CardDAV/CalDAV for phone contact and calendar apps, which cannot go through
# the SSO wall. Opened worldwide through local.path_bypasses (rules.tf). Read
# off Monica v3.7.0: laravel-sabre on `/dav` (config/laravelsabre.php), behind
# HTTP Basic where the password is a Monica personal access token
# (AuthenticateWithTokenOnBasicAuth), not the account password. The two
# `.well-known` paths answer a 301 to `/dav/` (routes/web.php).
#
# Monica only serves `/dav` when DAV_ENABLED=true in its .env, which this repo
# does not template (env_file: .env, written by hand on the host).
locals {
  monica_dav_paths = {
    "/dav/*"               = 4
    "/.well-known/carddav" = 4
    "/.well-known/caldav"  = 4
  }
}

resource "pangolin_target" "monica" {
  resource_id = pangolin_resource.monica.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "monica_v4"
  port        = 80
  method      = "http"

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_port                = 80
  hc_hostname            = "monica_v4"
  hc_path                = "/"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_access_token" "monica" {
  resource_id = pangolin_resource.monica.id
  title       = "Healthcheck ${pangolin_resource.monica.name}"
}

output "monica_access_token" {
  description = "MONICA - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.monica.id,
    token = pangolin_resource_access_token.monica.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http_keyword" "monica" {
  name = "Healthcheck ${pangolin_resource.monica.name}"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent          = uptimekuma_monitor_group.self_hosted.id
  url             = "https://${pangolin_resource.monica.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  # Pangolin's automatic maintenance page is a Next.js server component proxied
  # by a Traefik router at priority 2000, so a service that is completely down
  # answers 200 with that page instead of failing. A plain status-code monitor
  # reads that as UP and never sends the downtime mail - the exact alerting the
  # maintenance page was added on top of.
  #
  # Inverted keyword: finding the maintenance title means DOWN. The title is
  # rendered server-side into the HTML (src/app/maintenance-screen/page.tsx), so
  # it is visible to a plain GET, and it is the same local the resources use, so
  # editing the page text cannot leave the monitors matching a stale string.
  keyword        = local.maintenance.title
  invert_keyword = true
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.monica.id),
    "P-Access-Token"    = pangolin_resource_access_token.monica.token
  })
  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

resource "uptimekuma_monitor_push" "backup_monica" {
  name = "Backup ${pangolin_resource.monica.name}"

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

resource "uptimekuma_monitor_push" "cron_monica" {
  name = "Cron ${pangolin_resource.monica.name}"

  # Not a backup: grouped with the healthchecks. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval = 60 * 15

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

output "uptime_backup_monica_url" {
  description = "MONICA - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_monica.push_token}"
  sensitive   = true
}

output "uptime_cron_monica_url" {
  description = "MONICA - URL pour envoyer les heartbeats push du cron"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_monica.push_token}"
  sensitive   = true
}
