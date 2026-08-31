# ---------------------------------------------------------------------------
# Proxmox web UI.
#
# Created by hand in the Pangolin UI long before this configuration existed and
# left out of it: it was pinned by id in `local.unmanaged_resources` so the geo
# rules would still cover it, while the resource itself, its target and its
# Uptime Kuma monitor stayed outside the code. Declared here so all three are
# managed like every other public resource.
#
# Values mirror GET /v1/resource/4 and /v1/resource/4/targets, so the import
# below is a no-op apart from the monitor (see the bottom of this file).
# ---------------------------------------------------------------------------

resource "pangolin_resource" "proxmox" {
  name      = "00NTF - Proxmox"
  subdomain = "proxmox"
  domain_id = local.domain_ids["sylvain.cloud"]
  protocol  = "tcp"
  mode      = "http"
  sso       = true

  # False in Pangolin, mirrored rather than "fixed": flipping it to true would
  # start enforcing the country rules that rules.tf already creates for this
  # resource, which is a live access change, not a refactor. See the note in
  # local.managed_resources.
  apply_rules = false

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
}

resource "pangolin_target" "proxmox" {
  resource_id = pangolin_resource.proxmox.id
  site_id     = pangolin_site.proxmox_lxc.id
  ip          = "pve.sylvain.cloud"
  port        = 8006
  method      = "https"
  priority    = 100

  # Probe settings copied from the live target rather than normalised to the
  # 30s / 2 / 3 used elsewhere in this directory: this is an import, and a
  # tighter probe on the hypervisor UI is a deliberate choice worth keeping.
  #
  # `hc_status` is left undeclared: Pangolin holds null (accept any status) and
  # an optional+computed attribute cannot be pinned to null. Setting it to 200
  # would tighten the probe on a resource being imported blind - a separate,
  # explicit decision.
  hc_enabled             = true
  hc_scheme              = "https"
  hc_mode                = "http"
  hc_hostname            = "pve.sylvain.cloud"
  hc_port                = 8006
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

# The live monitor (id 56) carries a hand-made access token, sits in the old
# "Auto-Hébergé" group and has no notification attached at all - it has never
# been able to page anyone. It is not imported: a fresh token and monitor built
# to the same shape as the other sixteen is what "rapatrier" means here. Delete
# monitor 56 and its access token once this is applied.
resource "pangolin_resource_access_token" "proxmox" {
  resource_id = pangolin_resource.proxmox.id
  title       = "Healthcheck ${pangolin_resource.proxmox.name}"
}

resource "uptimekuma_monitor_http_keyword" "proxmox" {
  name = "Healthcheck ${pangolin_resource.proxmox.name}"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  url             = "https://${pangolin_resource.proxmox.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  # Inverted keyword, same reasoning as the other healthchecks. See the comment
  # in website_betisier.tf.
  keyword        = local.maintenance.title
  invert_keyword = true
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.proxmox.id),
    "P-Access-Token"    = pangolin_resource_access_token.proxmox.token
  })
  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}
