# Public showcase of Planning Équipes, exemple-planning.sylvain.dev: the
# instance the product's web page links to. Deployed by the same Ansible role
# as production (ansible/flip.yml, fourth application of flip_planning), on
# fictional data reset every night to a pre-solved reference database.
#
# What sets it apart from website_demo_planning.tf, which it otherwise mirrors:
#
# - `sso = false`. A prospect follows a link from the web page and lands on the
#   application's own login, whose password the page prints. The country rules
#   still apply (rules.tf), like on every resource.
# - No pgAdmin target (the instance runs without it) and no /db route.
# - DROP rules on what a visitor holding the admin password must not reach, in
#   the band evaluated before the country rules (priorities 1 - 9, see
#   rules.tf): ahead of them because those only PASS, and a DROP behind a PASS
#   would never be read.
# - No Borg backup, hence no push monitor: the database is dropped every night.
# - The requests that start a solve go through a quota guard (see below).
resource "pangolin_resource" "exemple_planning" {
  name        = "Exemple Planning"
  subdomain   = "exemple-planning"
  domain_id   = local.domain_ids["sylvain.dev"]
  protocol    = "tcp"
  mode        = "http"
  sso         = false
  apply_rules = true

  # Optional+computed: pinned so a plan can disagree with the API. See
  # resource_defaults.tf.
  ssl                     = local.resource_pins.ssl
  enabled                 = local.resource_pins.enabled
  block_access            = local.resource_pins.block_access
  email_whitelist_enabled = local.resource_pins.email_whitelist_enabled
  sticky_session          = local.resource_pins.sticky_session

  # Maintenance screen served automatically while no target is healthy - which
  # includes the minute of the nightly reset. See maintenance.tf.
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

# What the shared admin password must not open, path by path. The application
# would let an administrator do each of these; on an instance whose
# administrator is anyone who read the web page, they stop at the proxy.
locals {
  exemple_planning_dropped_paths = {
    # The MCP server. The instance has no API key, so the application already
    # answers 401; dropping it here keeps the endpoint from being probed at all.
    mcp = { priority = 1, value = "/mcp/*" }
    # The SQL dump routes. The import accepts INSERT/DELETE/TRUNCATE on the
    # application's tables only, but an INSERT ... SELECT can still call any
    # function, and the compose stack's database user is a PostgreSQL
    # superuser: server-side file reads and writes are one statement away.
    database = { priority = 2, value = "/api/database/*" }
    # Outgoing webhooks (the first release after 1.4.0): a public form that makes the
    # host send signed HTTPS requests to any address a visitor types in.
    webhooks = { priority = 3, value = "/api/webhooks/*" }
    # The synchronous solve takes a whole problem in its body and is not what
    # the UI calls (it uses /api/solve/async*, under the 60 s ceiling and the
    # one-job queue). No wildcard: only that exact path.
    solve_sync = { priority = 4, value = "/api/solve" }
  }
}

resource "pangolin_resource_rule" "exemple_planning_drop" {
  for_each = local.exemple_planning_dropped_paths

  resource_id = pangolin_resource.exemple_planning.id
  action      = "DROP"
  match       = "PATH"
  value       = each.value.value
  priority    = each.value.priority
  enabled     = true
}

resource "pangolin_target" "exemple_planning" {
  resource_id = pangolin_resource.exemple_planning.id
  site_id     = pangolin_site.flip.id
  ip          = "exemple-planning"
  port        = 8080
  method      = "http"

  # Catch-all target, must have a lower priority than the sub-path ones.
  path            = "/"
  path_match_type = "prefix"
  priority        = 1

  # All three of hc_scheme / hc_mode / hc_port are sent explicitly: Pangolin
  # stores them as NULL otherwise and the probe never succeeds. See the
  # production file.
  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "exemple-planning"
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

# Mailpit, public on purpose: it is where a visitor reads the mails the
# showcase "sent" — a planning, an espace access code — since none leaves the
# host. Everything in it is fictional and emptied every night with the rest.
resource "pangolin_target" "exemple_planning_mailpit" {
  resource_id = pangolin_resource.exemple_planning.id
  site_id     = pangolin_site.flip.id
  ip          = "exemple-planning-mailpit"
  port        = 8025
  method      = "http"

  path            = "/mail"
  path_match_type = "prefix"
  priority        = 3

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "exemple-planning-mailpit"
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

# No branding image, but the nginx and this target stay so that every instance
# keeps the same shape. See website_demo_planning.tf.
resource "pangolin_target" "exemple_planning_assets" {
  resource_id = pangolin_resource.exemple_planning.id
  site_id     = pangolin_site.flip.id
  ip          = "exemple-planning-assets"
  port        = 80
  method      = "http"

  path            = "/assets"
  path_match_type = "prefix"
  priority        = 4

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "exemple-planning-assets"
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

# Kept although the resource has no SSO, like betisier: the monitor sends it
# all the same, and the resource keeps working if SSO is ever turned back on.
# The two prefixes under which a request can start a solve go through the
# instance's guard container first (Traefik, ansible flip_planning_solve_rate_limit):
# 12 solves an hour for all visitors together, the rest passed through as is.
# A stopgap until the application enforces its own quota. Pangolin's rules run
# before any target, so the DROP of the synchronous /api/solve above still holds.
locals {
  exemple_planning_guarded_paths = {
    solve    = { priority = 5, path = "/api/solve" }
    staffing = { priority = 6, path = "/api/staffing" }
  }
}

resource "pangolin_target" "exemple_planning_guard" {
  for_each = local.exemple_planning_guarded_paths

  resource_id = pangolin_resource.exemple_planning.id
  site_id     = pangolin_site.flip.id
  ip          = "exemple-planning-guard"
  port        = 80
  method      = "http"

  path            = each.value.path
  path_match_type = "prefix"
  priority        = each.value.priority

  # Traefik's own ping endpoint (--ping on the web entry point).
  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "exemple-planning-guard"
  hc_port                = 80
  hc_path                = "/ping"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_access_token" "exemple_planning" {
  resource_id = pangolin_resource.exemple_planning.id
  title       = "Healthcheck ${pangolin_resource.exemple_planning.name}"
}

output "exemple_planning_access_token" {
  description = "EXEMPLE_PLANNING - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.exemple_planning.id,
    token = pangolin_resource_access_token.exemple_planning.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http_keyword" "exemple_planning" {
  name = "Healthcheck ${pangolin_resource.exemple_planning.name}"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent          = uptimekuma_monitor_group.self_hosted.id
  url             = "https://${pangolin_resource.exemple_planning.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  # Inverted keyword: finding the maintenance title means DOWN. Pangolin's
  # maintenance page answers 200, so a plain status-code monitor would read a
  # dead service as UP. See website_flip_planning.tf. Two retries a minute
  # apart ride out the nightly reset.
  keyword        = local.maintenance.title
  invert_keyword = true
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.exemple_planning.id),
    "P-Access-Token"    = pangolin_resource_access_token.exemple_planning.token
  })
  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}
