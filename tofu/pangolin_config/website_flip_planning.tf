resource "pangolin_resource" "flip_planning" {
  name        = "Flip Planning"
  subdomain   = "flip-planning"
  domain_id   = local.domain_ids["sylvain.cloud"]
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

  # No custom header any more: X-Pangolin was set by hand in the Pangolin UI
  # for the application's MCP guard, which no longer requires it. Removing it
  # is a manual step in the UI, not an apply - the provider cannot round-trip
  # an emptied header list (the update response comes back as a string, not a
  # list) and fails with "cannot unmarshal string into ... headers of type
  # []ResourceHeader". Ignoring the attribute keeps Tofu from ever sending one.
  lifecycle {
    ignore_changes = [headers]
  }
}

resource "pangolin_resource_role" "flip_planning" {
  resource_id = pangolin_resource.flip_planning.id
  role_id     = pangolin_role.apps["flip-planning"].id
}

# The MCP server (`POST /mcp`, `GET /mcp/sse`) is driven by hosted assistants -
# Claude, ChatGPT, Le Chat, Gemini. Only Anthropic publishes a stable egress
# range, which is why this used to be an ACCEPT on CIDR 160.79.104.0/21: every
# other assistant was dropped by the catch-all `DROP COUNTRY ALL` (priority 99,
# in rules.tf), and calling from FR/DE would not have helped either - the
# country rules only PASS, so the request landed on the SSO wall with no
# session to show it.
#
# Matching on the path instead of on the caller takes geography out of the
# question. Priority 1 puts this ahead of the country rules so it decides first
# whatever the origin - they only PASS, so a request from FR or DE would
# otherwise never reach it - and ACCEPT short-circuits authentication outright:
# Pangolin evaluates rules before SSO, and an ACCEPT returns "allowed" without
# running any auth method. It heads the bypass band described in rules.tf; the
# provider rejects priority 0, which is why the country rules start at 10.
#
# This opens /mcp to the internet as far as Pangolin is concerned; it does not
# open the MCP server. The application still demands its own shared key
# (PLANNING_MCP_API_KEY, header X-Api-Key) and answers 401 without it. The
# exposure is limited to that prefix: the UI, pgAdmin (/db), Mailpit (/mail)
# and the assets keep both the SSO wall and the geo-filter.
#
# `/mcp/*` covers `/mcp` itself as well as everything under it - Pangolin's
# matcher lets a trailing `*` segment match zero segments (server/lib/
# pathMatch.ts).
#
# Unlike the country rules this one is app-specific, hence a standalone resource
# here rather than an entry in the generic loops of rules.tf.
resource "pangolin_resource_rule" "flip_planning_mcp" {
  resource_id = pangolin_resource.flip_planning.id
  action      = "ACCEPT"
  match       = "PATH"
  value       = "/mcp/*"
  priority    = 1
  enabled     = true
}

resource "pangolin_target" "flip_planning" {
  resource_id = pangolin_resource.flip_planning.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "flip-planning"
  port        = 8080
  method      = "http"

  # Catch-all target, must have a lower priority than the pgAdmin one.
  path            = "/"
  path_match_type = "prefix"
  priority        = 1

  # Health checks: `hc_scheme` / `hc_mode` / `hc_port` are optional+computed, and
  # Pangolin stores them as NULL when Tofu does not send them - it does not fill
  # in a default. A probe with no scheme never succeeds, so all three targets sat
  # at hcHealth="unhealthy" and Traefik dropped them from the load balancer
  # ("no available server"). Declared explicitly so the probes can actually run.
  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "flip-planning"
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

# pgAdmin is served on the /db sub-path of the same resource, so it is protected
# by the same SSO / role. pgAdmin is told about its root via SCRIPT_NAME=/db,
# hence no path rewrite here.
resource "pangolin_target" "flip_planning_pgadmin" {
  resource_id = pangolin_resource.flip_planning.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "flip-planning-pgadmin"
  port        = 80
  method      = "http"

  path            = "/db"
  path_match_type = "prefix"
  priority        = 2

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "flip-planning-pgadmin"
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

resource "pangolin_target" "flip_planning_mailpit" {
  resource_id = pangolin_resource.flip_planning.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "flip-planning-mailpit"
  port        = 8025
  method      = "http"

  path            = "/mail"
  path_match_type = "prefix"
  priority        = 3

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "flip-planning-mailpit"
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

# The festival's visuals are part of the deployment, not of the image (the
# application repository carries no customer mark). They are the
# flip_planning_branding_* role parameters of this instance in
# ansible/docker.yml: copied next to the compose file, mounted read-only on the
# app container for the PDFs, and served to the browser by a small nginx on
# this sub-path - same resource, so the same SSO and the same role guard them.
resource "pangolin_target" "flip_planning_assets" {
  resource_id = pangolin_resource.flip_planning.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "flip-planning-assets"
  port        = 80
  method      = "http"

  path            = "/assets"
  path_match_type = "prefix"
  priority        = 4

  # No dedicated probe endpoint on a static server: the logo itself is the
  # healthcheck, and it is exactly the file whose absence would break the UI.
  # Its name is the basename of flip_planning_branding_logo in docker.yml.
  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "flip-planning-assets"
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

resource "pangolin_resource_access_token" "flip_planning" {
  resource_id = pangolin_resource.flip_planning.id
  title       = "Healthcheck ${pangolin_resource.flip_planning.name}"
}

output "flip_planning_access_token" {
  description = "FLIP_PLANNING - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.flip_planning.id,
    token = pangolin_resource_access_token.flip_planning.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http_keyword" "flip_planning" {
  name = "Healthcheck ${pangolin_resource.flip_planning.name}"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent          = uptimekuma_monitor_group.self_hosted.id
  url             = "https://${pangolin_resource.flip_planning.full_domain}"
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
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.flip_planning.id),
    "P-Access-Token"    = pangolin_resource_access_token.flip_planning.token
  })
  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

resource "uptimekuma_monitor_push" "backup_flip_planning" {
  name = "Backup ${pangolin_resource.flip_planning.name}"

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

output "uptime_backup_flip_planning_url" {
  description = "FLIP_PLANNING - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_flip_planning.push_token}"
  sensitive   = true
}
