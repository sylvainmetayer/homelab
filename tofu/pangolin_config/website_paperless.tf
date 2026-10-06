resource "pangolin_resource" "paperless" {
  name        = "Paperless-ngx"
  subdomain   = "papiers"
  domain_id   = local.domain_ids["sylvain.cloud"]
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

resource "pangolin_resource_role" "paperless" {
  resource_id = pangolin_resource.paperless.id
  role_id     = pangolin_role.apps["paperless"].id
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

resource "pangolin_target" "paperless" {
  resource_id = pangolin_resource.paperless.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "paperless"
  port        = 8000
  method      = "http"

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_port                = 8000
  hc_hostname            = "paperless"
  hc_path                = "/"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_access_token" "paperless" {
  resource_id = pangolin_resource.paperless.id
  title       = "Healthcheck ${pangolin_resource.paperless.name}"
}

output "paperless_access_token" {
  description = "PAPERLESS - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.paperless.id,
    token = pangolin_resource_access_token.paperless.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http_keyword" "paperless" {
  name = "Healthcheck ${pangolin_resource.paperless.name}"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent          = uptimekuma_monitor_group.self_hosted.id
  url             = "https://${pangolin_resource.paperless.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  # Inverted keyword on the maintenance title. See maintenance.tf.
  keyword        = local.maintenance.title
  invert_keyword = true
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.paperless.id),
    "P-Access-Token"    = pangolin_resource_access_token.paperless.token
  })
  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

resource "uptimekuma_monitor_push" "backup_paperless" {
  name = "Backup ${pangolin_resource.paperless.name}"

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

output "uptime_backup_paperless_url" {
  description = "PAPERLESS - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_paperless.push_token}"
  sensitive   = true
}
