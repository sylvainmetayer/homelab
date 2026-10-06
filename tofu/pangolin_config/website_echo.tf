resource "pangolin_resource" "echo" {
  name        = "Echo"
  subdomain   = "echo"
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

resource "pangolin_resource_role" "echo" {
  resource_id = pangolin_resource.echo.id
  role_id     = pangolin_role.apps["echo"].id
}

resource "pangolin_target" "echo" {
  resource_id = pangolin_resource.echo.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "echo"
  port        = 80
  method      = "http"

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_port                = 80
  hc_hostname            = "echo"
  hc_path                = "/"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_access_token" "echo" {
  resource_id = pangolin_resource.echo.id
  title       = "Healthcheck ${pangolin_resource.echo.name}"
}

output "echo_access_token" {
  description = "ECHO - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.echo.id,
    token = pangolin_resource_access_token.echo.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http_keyword" "echo" {
  name = "Healthcheck ${pangolin_resource.echo.name}"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent          = uptimekuma_monitor_group.self_hosted.id
  url             = "https://${pangolin_resource.echo.full_domain}"
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
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.echo.id),
    "P-Access-Token"    = pangolin_resource_access_token.echo.token
  })
  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}
