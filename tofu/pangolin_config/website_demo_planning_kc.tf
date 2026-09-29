# TEMPORARY third instance of Flip Planning, demo-planning-kc.sylvain.dev: the
# application pull request that makes Keycloak mandatory, tested on a real
# domain in HTTPS (passkeys need it) with its own Keycloak on the /auth
# sub-path. Deployed by the same Ansible role (ansible/flip.yml). Same shape as
# website_demo_planning.tf, minus what a test bench does not need: no MCP
# bypass, no backup push monitor. Torn down with the remove-app skill once the
# pull request is merged.
resource "pangolin_resource" "demo_planning_kc" {
  name        = "Demo Planning KC"
  subdomain   = "demo-planning-kc"
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

  # Same reason as the other two resources: the provider cannot round-trip an
  # emptied header list, so the attribute is never sent.
  lifecycle {
    ignore_changes = [headers]
  }
}

resource "pangolin_resource_role" "demo_planning_kc" {
  resource_id = pangolin_resource.demo_planning_kc.id
  role_id     = pangolin_role.apps["demo-planning-kc"].id
}

# ---------------------------------------------------------------------------
# Carving /auth out of this resource's Pangolin SSO.
#
# The resource is `sso = true`: Pangolin demands its own login before anything
# reaches the origin. For an identity provider that is a deadlock, and not only
# for the browser: the application fetches the realm's discovery document and
# signing keys at startup, through this public URL and with no session of any
# kind. Behind the SSO those come back as Pangolin's HTML login page instead of
# JSON, discovery fails and the APPLICATION DOES NOT START.
#
# ACCEPT lifts it — Pangolin evaluates rules before SSO, and an ACCEPT returns
# "allowed" without running any auth method. Priority 2, in the band that is
# evaluated BEFORE the country rules (rules.tf): those only PASS, and the flip
# server calls from behind Pangolin's own NAT (no public address of its own),
# a source the country rules cannot be trusted to PASS — a rule behind them
# might never be reached, and the application would still not start.
#
# Two consequences, deliberate: /auth is not geo-filtered, and the Keycloak
# admin console (/auth/admin) is reachable with Keycloak's own login as its only
# guard. Acceptable for a temporary bench whose master realm is not the one
# people sign in to; production would narrow this to /auth/realms and
# /auth/resources before copying it.
#
# `/auth/*` covers `/auth` itself as well as everything under it (a trailing
# `*` segment matches zero segments, see website_flip_planning.tf).
resource "pangolin_resource_rule" "demo_planning_kc_keycloak" {
  resource_id = pangolin_resource.demo_planning_kc.id
  action      = "ACCEPT"
  match       = "PATH"
  value       = "/auth/*"
  priority    = 2
  enabled     = true
}

resource "pangolin_target" "demo_planning_kc" {
  resource_id = pangolin_resource.demo_planning_kc.id
  site_id     = pangolin_site.flip.id
  ip          = "demo-planning-kc"
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
  hc_hostname            = "demo-planning-kc"
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

resource "pangolin_target" "demo_planning_kc_pgadmin" {
  resource_id = pangolin_resource.demo_planning_kc.id
  site_id     = pangolin_site.flip.id
  ip          = "demo-planning-kc-pgadmin"
  port        = 80
  method      = "http"

  path            = "/db"
  path_match_type = "prefix"
  priority        = 2

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "demo-planning-kc-pgadmin"
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

# Mailpit catches what BOTH the application and Keycloak send — invitations,
# sign-in codes, resets — so /mail is where a tester reads them. Behind the
# SSO, like the rest.
resource "pangolin_target" "demo_planning_kc_mailpit" {
  resource_id = pangolin_resource.demo_planning_kc.id
  site_id     = pangolin_site.flip.id
  ip          = "demo-planning-kc-mailpit"
  port        = 8025
  method      = "http"

  path            = "/mail"
  path_match_type = "prefix"
  priority        = 3

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "demo-planning-kc-mailpit"
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

resource "pangolin_target" "demo_planning_kc_assets" {
  resource_id = pangolin_resource.demo_planning_kc.id
  site_id     = pangolin_site.flip.id
  ip          = "demo-planning-kc-assets"
  port        = 80
  method      = "http"

  path            = "/assets"
  path_match_type = "prefix"
  priority        = 4

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "demo-planning-kc-assets"
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

# Keycloak, on /auth. Its health endpoints live on the management port (9000),
# which KC_HTTP_RELATIVE_PATH prefixes too: /auth/health/ready, not
# /health/ready.
resource "pangolin_target" "demo_planning_kc_keycloak" {
  resource_id = pangolin_resource.demo_planning_kc.id
  site_id     = pangolin_site.flip.id
  ip          = "demo-planning-kc-keycloak"
  port        = 8080
  method      = "http"

  path            = "/auth"
  path_match_type = "prefix"
  priority        = 5

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "demo-planning-kc-keycloak"
  hc_port                = 9000
  hc_path                = "/auth/health/ready"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}
