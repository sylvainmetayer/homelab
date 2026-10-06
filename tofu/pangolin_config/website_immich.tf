resource "pangolin_resource" "immich" {
  name        = "Immich"
  subdomain   = "photos"
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

resource "pangolin_resource_role" "immich" {
  resource_id = pangolin_resource.immich.id
  role_id     = pangolin_role.apps["immich"].id
}

resource "pangolin_target" "immich" {
  resource_id = pangolin_resource.immich.id
  site_id     = pangolin_site.pi.id
  ip          = "immich_server"
  port        = 2283
  method      = "http"

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_port                = 2283
  hc_hostname            = "immich_server"
  hc_path                = "/"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_pincode" "immich" {
  resource_id = pangolin_resource.immich.id
  pincode     = tostring(local.immich_pin)
}

# Priority 9: the last slot before the `PASS COUNTRY` rules generated in
# rules.tf (FR at 10, DE at 11). It used to sit at 12, just behind them, where
# it was never reached: the home connection is French, so the FR PASS matched
# first and sent it to the SSO wall like anybody else. Ahead of the country
# rules it does what it says - the home connection gets in by IP, without
# SSO. Only the backslash DROP of rules.tf (priority 1) comes before it.
#
# What that trusts, deliberately: every device behind the home connection
# (guest Wi-Fi included) gets Immich, Dawarich and TREK without SSO, and
# without Immich's pincode. And the address, not the house: if the ISP hands
# home_ip (secrets.sops.yaml) to someone else - a new lease, CGNAT - they get
# the same, until home_ip is updated AND pangolin_config applied (nothing
# applies it on a schedule). Change home_ip as soon as the line's IP changes.
resource "pangolin_resource_rule" "immich_home_ip" {
  resource_id = pangolin_resource.immich.id
  action      = "ACCEPT"
  match       = "IP"
  value       = local.home_ip
  priority    = 9
  enabled     = true
}

resource "pangolin_resource_access_token" "immich" {
  resource_id = pangolin_resource.immich.id
  title       = "Healthcheck ${pangolin_resource.immich.name}"
}

output "immich_access_token" {
  description = "IMMICH - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.immich.id,
    token = pangolin_resource_access_token.immich.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http_keyword" "immich" {
  name = "Healthcheck ${pangolin_resource.immich.name}"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent          = uptimekuma_monitor_group.self_hosted.id
  url             = "https://${pangolin_resource.immich.full_domain}"
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
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.immich.id),
    "P-Access-Token"    = pangolin_resource_access_token.immich.token
  })
  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

resource "uptimekuma_monitor_push" "backup_immich" {
  name = "Backup ${pangolin_resource.immich.name}"

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

output "uptime_backup_immich_url" {
  description = "IMMICH - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_immich.push_token}"
  sensitive   = true
}
