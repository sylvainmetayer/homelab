# ---------------------------------------------------------------------------
# Healthchecks for Pangolin resources this configuration does not own.
#
# `SSH PI` (38) is the last resource still pinned by id in
# `local.unmanaged_resources`: its rules are managed here, the resource is not.
# It is left out of the `00NTF` rapatriation because it is a `mode = "ssh"`
# bastion, not an HTTP resource - `pam_mode`, `auth_daemon_*` and an ssh-mode
# target make it a different shape from every other block in this directory.
#
# Deliberately `uptimekuma_monitor_http` and not the inverted-keyword form used
# by the managed healthchecks: this resource has no maintenance page, so a
# service that is down still answers with Traefik's error rather than a 200, and
# there is no maintenance title to match on. Giving it
# `maintenance_mode_enabled = true` later means converting this monitor to
# uptimekuma_monitor_http_keyword at the same time.
# ---------------------------------------------------------------------------

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
