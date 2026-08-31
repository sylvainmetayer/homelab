# ---------------------------------------------------------------------------
# Bbox router admin UI. Was `00NTF - BBOX`.
#
# Disabled in Pangolin and mirrored that way: `enabled = false` is the live
# state, not an oversight, so it is written literally rather than taken from
# local.resource_pins. No healthcheck monitor either - there is nothing to watch
# on a resource Pangolin does not serve.
#
# Values mirror GET /v1/resource/15 and /v1/resource/15/targets.
# ---------------------------------------------------------------------------

resource "pangolin_resource" "bbox" {
  name        = "BBOX"
  subdomain   = "bbox"
  domain_id   = local.domain_ids["sylvain.cloud"]
  protocol    = "tcp"
  mode        = "http"
  sso         = true
  apply_rules = true

  # Disabled live. The other four pins are shared.
  enabled                 = false
  ssl                     = local.resource_pins.ssl
  block_access            = local.resource_pins.block_access
  email_whitelist_enabled = local.resource_pins.email_whitelist_enabled
  sticky_session          = local.resource_pins.sticky_session

  # See maintenance.tf. Declared for uniformity; a disabled resource is not
  # served at all, so nothing reaches the maintenance screen either.
  maintenance_mode_enabled = local.maintenance.enabled
  maintenance_mode_type    = local.maintenance.type
  maintenance_title        = local.maintenance.title
  maintenance_message      = local.maintenance.message
}

resource "pangolin_target" "bbox" {
  resource_id = pangolin_resource.bbox.id
  site_id     = pangolin_site.pi.id
  ip          = "192.168.1.254"
  port        = 80
  method      = "http"
  priority    = 100

  # Probe fields are populated live but `hc_enabled` is false, so they are inert
  # settings kept from an earlier attempt. Mirrored as-is rather than dropped:
  # they are optional+computed, and clearing them is not expressible.
  hc_enabled             = false
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "192.168.1.254"
  hc_port                = 80
  hc_path                = "/"
  hc_method              = "GET"
  hc_interval            = 5
  hc_unhealthy_interval  = 30
  hc_timeout             = 5
  hc_healthy_threshold   = 1
  hc_unhealthy_threshold = 1
  hc_follow_redirects    = true
  hc_tls_server_name     = ""
}
