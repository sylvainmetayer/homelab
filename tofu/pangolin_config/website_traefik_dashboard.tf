# ---------------------------------------------------------------------------
# Traefik dashboard. Was `00NTF - Dashboard Traefik`.
#
# Disabled in Pangolin, mirrored. Its target is the only one in this directory
# that points at the Pangolin host itself (`gerbil`, the reverse proxy) over the
# `local` site declared in nodes.tf, rather than at a newt-connected node.
#
# Values mirror GET /v1/resource/2 and /v1/resource/2/targets.
# ---------------------------------------------------------------------------

resource "pangolin_resource" "traefik_dashboard" {
  name      = "Dashboard Traefik"
  subdomain = "dashboard"
  domain_id = local.domain_ids["sylvain.cloud"]
  protocol  = "tcp"
  mode      = "http"
  sso       = true

  # False in Pangolin, mirrored - same reasoning as Proxmox and NAS.
  apply_rules = false

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

resource "pangolin_target" "traefik_dashboard" {
  resource_id = pangolin_resource.traefik_dashboard.id
  site_id     = pangolin_site.pangolin.id
  ip          = "gerbil"
  port        = 8080
  method      = "http"
  priority    = 100

  hc_enabled = false
}
