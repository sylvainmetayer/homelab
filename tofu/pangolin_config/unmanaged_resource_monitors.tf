# ---------------------------------------------------------------------------
# Healthchecks for Pangolin resources this configuration does not own.
#
# `00NTF - NAS` (75) and `SSH PI` (38) were created by hand and are still only
# pinned by id in `local.unmanaged_resources`, so their rules are managed here
# but the resources are not. They were the inverse of the Proxmox blind spot:
# publicly reachable, enabled, and watched by nobody.
#
# Only the access token and the monitor are declared. Importing the resources
# themselves is the natural follow-up - see website_proxmox.tf for the shape -
# but it means deciding what `apply_rules` and the maintenance page should be on
# an infrastructure endpoint, which is a separate call.
#
# Deliberately `uptimekuma_monitor_http` and not the inverted-keyword form used
# by the seventeen managed healthchecks: neither resource has the maintenance
# page enabled, so a service that is down still answers with Traefik's error
# rather than a 200, and there is no maintenance title to match on.
#
# If either resource is ever given `maintenance_mode_enabled = true`, these two
# monitors go blind exactly as the others would have - convert them to
# uptimekuma_monitor_http_keyword at that point.
# ---------------------------------------------------------------------------

resource "pangolin_resource_access_token" "nas" {
  resource_id = local.unmanaged_resources["00NTF - NAS"]
  title       = "Healthcheck 00NTF - NAS"
}

# Full domain hardcoded: without a pangolin_resource block there is no
# `full_domain` attribute to read it from.
resource "uptimekuma_monitor_http" "nas" {
  name = "Healthcheck 00NTF - NAS"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  url             = "https://nas.sylvain.cloud"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.nas.id),
    "P-Access-Token"    = pangolin_resource_access_token.nas.token
  })
  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

resource "pangolin_resource_access_token" "ssh_pi" {
  resource_id = local.unmanaged_resources["SSH PI"]
  title       = "Healthcheck SSH PI"
}

# `SSH PI` is a `mode = "ssh"` resource: Pangolin serves it through the browser
# gateway web UI rather than proxying to a backend, so remote.sylvain.cloud is a
# real HTTP endpoint (it answers 401 unauthenticated, i.e. the router exists and
# the auth layer is in front of it). This checks that the gateway is reachable
# and authorised - not that sshd on the far side is alive, which the resource
# has no health check for either (`hc_enabled = false` on target 40).
resource "uptimekuma_monitor_http" "ssh_pi" {
  name = "Healthcheck SSH PI"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  url             = "https://remote.sylvain.cloud"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.ssh_pi.id),
    "P-Access-Token"    = pangolin_resource_access_token.ssh_pi.token
  })
  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}
