# ---------------------------------------------------------------------------
# NAS admin UI.
#
# Was `00NTF - NAS`, pinned by id in local.unmanaged_resources. Declared here so
# the "00NTF" ("00 - non terraform") prefix could be dropped: see the runbook in
# the commit message - the live rename has to happen before this applies, or the
# coverage precondition in rules.tf fails on a name it no longer knows.
#
# Values mirror GET /v1/resource/75 and /v1/resource/75/targets.
# ---------------------------------------------------------------------------

resource "pangolin_resource" "nas" {
  name      = "NAS"
  subdomain = "nas"
  domain_id = local.domain_ids["sylvain.cloud"]
  protocol  = "tcp"
  mode      = "http"
  sso       = true

  # False in Pangolin, mirrored rather than "fixed" - same reasoning as Proxmox.
  apply_rules = false

  # Optional+computed: pinned so a plan can disagree with the API. See
  # resource_defaults.tf.
  ssl                     = local.resource_pins.ssl
  enabled                 = local.resource_pins.enabled
  block_access            = local.resource_pins.block_access
  email_whitelist_enabled = local.resource_pins.email_whitelist_enabled
  sticky_session          = local.resource_pins.sticky_session

  # Maintenance screen served automatically while no target is healthy.
  # See maintenance.tf. Inert as long as the target below has no health check:
  # Pangolin reads an unprobed target as "unknown", not "unhealthy", so it never
  # counts as down. Enabling hc_* here would make both this and the monitor
  # meaningful - a separate decision on an infrastructure endpoint.
  maintenance_mode_enabled = local.maintenance.enabled
  maintenance_mode_type    = local.maintenance.type
  maintenance_title        = local.maintenance.title
  maintenance_message      = local.maintenance.message
}

resource "pangolin_target" "nas" {
  resource_id = pangolin_resource.nas.id
  site_id     = pangolin_site.proxmox_lxc.id
  ip          = "192.168.1.137"
  port        = 9999
  method      = "http"
  priority    = 100

  # No probe live, mirrored. See the note on the maintenance block above.
  hc_enabled = false
}

resource "pangolin_resource_access_token" "nas" {
  resource_id = pangolin_resource.nas.id
  title       = "Healthcheck ${pangolin_resource.nas.name}"
}

# Inverted keyword like the other managed healthchecks: this resource now serves
# the maintenance page, so a plain status monitor would read a down service as
# UP. The NAS answers 307 to /, Uptime Kuma follows redirects by default and
# lands on /desktop/ with a 200.
resource "uptimekuma_monitor_http_keyword" "nas" {
  name = "Healthcheck ${pangolin_resource.nas.name}"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  url             = "https://${pangolin_resource.nas.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  keyword        = local.maintenance.title
  invert_keyword = true
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.nas.id),
    "P-Access-Token"    = pangolin_resource_access_token.nas.token
  })
  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}
