# Gramps is stopped on purpose (gramps_enabled: false in
# ansible/host_vars/docker/variables.yaml, data and role kept). This one local
# says so for the whole file: Pangolin stops serving the resource rather than
# showing the maintenance page to whoever still has the link, and the
# healthcheck monitor, which could only be DOWN, is paused. The resource stays
# in local.managed_resources: its country rules stay in place for the day it
# comes back, and the coverage audit only looks at enabled resources anyway.
# A test pins it to gramps_enabled; flip both together.
locals {
  gramps_enabled = false
}

resource "pangolin_resource" "gramps" {
  name        = "Gramps"
  subdomain   = "trees"
  domain_id   = local.domain_ids["sylvain.cloud"]
  protocol    = "tcp"
  sso         = true
  apply_rules = true

  # Optional+computed: pinned so a plan can disagree with the API. See
  # resource_defaults.tf.
  mode = local.resource_pins.mode
  ssl  = local.resource_pins.ssl

  # Overrides the pin: see local.gramps_enabled below.
  enabled = local.gramps_enabled

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

resource "pangolin_resource_role" "gramps" {
  resource_id = pangolin_resource.gramps.id
  role_id     = pangolin_role.apps["gramps"].id
}

resource "pangolin_target" "gramps" {
  resource_id = pangolin_resource.gramps.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "grampsweb"
  port        = 5000
  method      = "http"

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_port                = 5000
  hc_hostname            = "grampsweb"
  hc_path                = "/"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_access_token" "gramps" {
  resource_id = pangolin_resource.gramps.id
  title       = "Healthcheck ${pangolin_resource.gramps.name}"
}

output "gramps_access_token" {
  description = "GRAMPS - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.gramps.id,
    token = pangolin_resource_access_token.gramps.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http_keyword" "gramps" {
  name = "Healthcheck ${pangolin_resource.gramps.name}"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent          = uptimekuma_monitor_group.self_hosted.id
  url             = "https://${pangolin_resource.gramps.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  # Stopped with the resource (local.gramps_enabled): it could only be DOWN
  # and mailing.
  active = local.gramps_enabled
  method = "GET"

  # Inverted keyword on the maintenance title. See maintenance.tf.
  keyword        = local.maintenance.title
  invert_keyword = true
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.gramps.id),
    "P-Access-Token"    = pangolin_resource_access_token.gramps.token
  })
  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

resource "uptimekuma_monitor_push" "backup_gramps" {
  name = "Backup ${pangolin_resource.gramps.name}"

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  interval = 60 * 60 * 24

  retry_interval = 20

  # Active even while Gramps is stopped: gramps_backup_enabled stays true in
  # host_vars, borgmatic still archives the (frozen) data every night, and an
  # inactive monitor would refuse its push - a failing Gramps backup would
  # page nobody. Follows gramps_backup_enabled, not local.gramps_enabled.
  active = true

  tags = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

output "uptime_backup_gramps_url" {
  description = "GRAMPS - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_gramps.push_token}"
  sensitive   = true
}
