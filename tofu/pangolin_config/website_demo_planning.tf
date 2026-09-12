# Demo environment of Flip Planning, on demo-planning.sylvain.dev.
#
# Same shape as website_flip_planning.tf — the two environments come from one
# Ansible role applied twice (see ansible/docker.yml), so the only thing that
# distinguishes them here is the subdomain, the domain and the container names
# the targets resolve on the newt network.
#
# It carries its own Pangolin role, so demo access can be granted to someone who
# has no business seeing the real planning.
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

  # PLANNING_MCP_REQUIRED_HEADERS in the app's .env refuses any request that
  # reached the origin without this header, so the MCP server is unreachable
  # except through the proxy. Declared here for the same reason as on the
  # production resource: the provider cannot round-trip an emptied header list.
  headers = [
    {
      name  = "X-Pangolin"
      value = "true"
    },
  ]

  # Maintenance screen served automatically while no target is healthy.
  # See maintenance.tf.
  maintenance_mode_enabled = local.maintenance.enabled
  maintenance_mode_type    = local.maintenance.type
  maintenance_title        = local.maintenance.title
  maintenance_message      = local.maintenance.message
}

resource "pangolin_resource_role" "demo_planning" {
  resource_id = pangolin_resource.demo_planning.id
  role_id     = pangolin_role.apps["demo-planning"].id
}

# Same rescue as on the production resource: Anthropic's egress range is outside
# FR/DE, so the catch-all `DROP COUNTRY ALL` (priority 99, rules.tf) would block
# Claude from reaching this instance's MCP server. Priority 98 sits just above
# that catch-all and below the country PASS rules.
resource "pangolin_resource_rule" "demo_planning_claude" {
  resource_id = pangolin_resource.demo_planning.id
  action      = "ACCEPT"
  match       = "CIDR"
  value       = "160.79.104.0/21"
  priority    = 98
  enabled     = true
}

resource "pangolin_target" "demo_planning" {
  resource_id = pangolin_resource.demo_planning.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "demo-planning"
  port        = 8080
  method      = "http"

  # Catch-all target, must have a lower priority than the sub-path ones.
  path            = "/"
  path_match_type = "prefix"
  priority        = 1

  # `hc_scheme` / `hc_mode` / `hc_port` are optional+computed and Pangolin stores
  # them as NULL when Tofu does not send them, which leaves the probe unable to
  # run and the target permanently unhealthy. Declared explicitly, as everywhere.
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

# pgAdmin on the /db sub-path of the same resource, so the same SSO and the same
# role guard it. SCRIPT_NAME=/db tells pgAdmin its root, hence no path rewrite.
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

# Mailpit, the SMTP sink. It matters more here than in production: a demo is
# where someone types a real address into the espace animateur form.
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

# The branding assets, served by the instance's own nginx. Same files as
# production (the Ansible role copies them from its own directory), different
# container.
resource "pangolin_target" "demo_planning_assets" {
  resource_id = pangolin_resource.demo_planning.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "demo-planning-assets"
  port        = 80
  method      = "http"

  path            = "/assets"
  path_match_type = "prefix"
  priority        = 4

  # No dedicated probe endpoint on a static server: the logo itself is the
  # healthcheck, and it is exactly the file whose absence would break the UI.
  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "demo-planning-assets"
  hc_port                = 80
  hc_path                = "/assets/flip.png"
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

  # Inverted keyword: Pangolin's maintenance page answers 200, so a plain
  # status-code monitor reads a dead service as UP. Finding the maintenance
  # title means DOWN. See website_flip_planning.tf for the full explanation.
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
