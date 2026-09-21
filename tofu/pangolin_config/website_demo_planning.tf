# Demo instance of Flip Planning, deployed by the same Ansible role as the
# production one (ansible/docker.yml applies it twice). This file mirrors
# website_flip_planning.tf: keep the two in step, and keep the `ip` /
# `hc_hostname` values in step with flip_planning_container_prefix.
resource "pangolin_resource" "demo_planning" {
  name        = "Demo Planning"
  subdomain   = "demo-planning"
  domain_id   = local.domain_ids["sylvain.dev"]
  protocol    = "tcp"
  mode        = "http"
  sso         = true
  apply_rules = true

  # Optional+computed: pinned so a plan can disagree with the API. See
  # resource_defaults.tf.
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

  # Same reason as the production resource: the provider cannot round-trip an
  # emptied header list, so the attribute is never sent.
  lifecycle {
    ignore_changes = [headers]
  }
}

resource "pangolin_resource_role" "demo_planning" {
  resource_id = pangolin_resource.demo_planning.id
  role_id     = pangolin_role.apps["demo-planning"].id
}

# Same path-based bypass as the production resource, and for the same reason:
# hosted assistants drive the MCP server and only Anthropic publishes a stable
# egress range, so matching on the caller would drop every other one on the
# catch-all `DROP COUNTRY ALL`. See the long comment in website_flip_planning.tf.
#
# The demo instance has its own PLANNING_MCP_API_KEY, so opening the prefix here
# does not open the production MCP server, and vice versa.
resource "pangolin_resource_rule" "demo_planning_mcp" {
  resource_id = pangolin_resource.demo_planning.id
  action      = "ACCEPT"
  match       = "PATH"
  value       = "/mcp/*"
  priority    = 1
  enabled     = true
}

resource "pangolin_target" "demo_planning" {
  resource_id = pangolin_resource.demo_planning.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "demo-planning"
  port        = 8080
  method      = "http"

  # Catch-all target, must have a lower priority than the pgAdmin one.
  path            = "/"
  path_match_type = "prefix"
  priority        = 1

  # All three of hc_scheme / hc_mode / hc_port are sent explicitly: Pangolin
  # stores them as NULL otherwise and the probe never succeeds. See the
  # production file.
  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "demo-planning"
  hc_port                = 8080
  hc_path                = "/"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

# pgAdmin on the /db sub-path of the same resource, hence the same SSO / role.
# SCRIPT_NAME=/db tells pgAdmin its root, so no path rewrite here.
resource "pangolin_target" "demo_planning_pgadmin" {
  resource_id = pangolin_resource.demo_planning.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "demo-planning-pgadmin"
  port        = 80
  method      = "http"

  path            = "/db"
  path_match_type = "prefix"
  priority        = 2

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "demo-planning-pgadmin"
  hc_port                = 80
  hc_path                = "/db/misc/ping"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_target" "demo_planning_mailpit" {
  resource_id = pangolin_resource.demo_planning.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "demo-planning-mailpit"
  port        = 8025
  method      = "http"

  path            = "/mail"
  path_match_type = "prefix"
  priority        = 3

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "demo-planning-mailpit"
  hc_port                = 8025
  hc_path                = "/mail/livez"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

# The demo declares no branding image (ansible/docker.yml leaves the
# flip_planning_branding_* parameters at their empty defaults): its assets
# directory is empty and the application shows no logo. The nginx and this
# target stay, so that the two instances keep the same shape and a demo that
# one day gets its own visuals needs no routing change.
resource "pangolin_target" "demo_planning_assets" {
  resource_id = pangolin_resource.demo_planning.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "demo-planning-assets"
  port        = 80
  method      = "http"

  path            = "/assets"
  path_match_type = "prefix"
  priority        = 4

  # Nothing to probe under /assets on an unbranded instance: nginx's own
  # default page answers on /, which is enough to tell the container is up.
  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "demo-planning-assets"
  hc_port                = 80
  hc_path                = "/"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_access_token" "demo_planning" {
  resource_id = pangolin_resource.demo_planning.id
  title       = "Healthcheck ${pangolin_resource.demo_planning.name}"
}

output "demo_planning_access_token" {
  description = "DEMO_PLANNING - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.demo_planning.id,
    token = pangolin_resource_access_token.demo_planning.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http_keyword" "demo_planning" {
  name = "Healthcheck ${pangolin_resource.demo_planning.name}"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent          = uptimekuma_monitor_group.self_hosted.id
  url             = "https://${pangolin_resource.demo_planning.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  # Inverted keyword: finding the maintenance title means DOWN. Pangolin's
  # maintenance page answers 200, so a plain status-code monitor would read a
  # dead service as UP. See website_flip_planning.tf.
  keyword        = local.maintenance.title
  invert_keyword = true
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.demo_planning.id),
    "P-Access-Token"    = pangolin_resource_access_token.demo_planning.token
  })
  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

resource "uptimekuma_monitor_push" "backup_demo_planning" {
  name = "Backup ${pangolin_resource.demo_planning.name}"

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

output "uptime_backup_demo_planning_url" {
  description = "DEMO_PLANNING - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_demo_planning.push_token}"
  sensitive   = true
}
