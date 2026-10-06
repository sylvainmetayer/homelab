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

  # Overrides the pin: Gramps is stopped on purpose (gramps_enabled: false in
  # ansible/host_vars/docker/variables.yaml, data and role kept), so Pangolin
  # stops serving it rather than showing the maintenance page to whoever still
  # has the link. Still in local.managed_resources: its country rules stay in
  # place for the day it comes back, and the coverage audit only looks at
  # enabled resources anyway. Flip back to local.resource_pins.enabled together
  # with gramps_enabled and the two monitors below.
  enabled = false

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
  # Gramps is stopped on purpose (gramps_enabled: false in
  # ansible/host_vars/docker/variables.yaml) and its resource disabled above:
  # this monitor could only be DOWN and mailing. Flip all of them back together.
  active = false
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

  # Inactive while Gramps is stopped, with the healthcheck above. The only
  # exception to "every backup monitor is active" in
  # tests/invariants.tftest.hcl. Note that gramps_backup_enabled stays true in
  # host_vars: borgmatic still archives the (frozen) data every night and its
  # push to this inactive monitor is refused, which borgmatic only logs as a
  # warning - a failing Gramps backup pages nobody until this is flipped back.
  active = false

  tags = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

output "uptime_backup_gramps_url" {
  description = "GRAMPS - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_gramps.push_token}"
  sensitive   = true
}
