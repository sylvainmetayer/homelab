resource "pangolin_resource" "dawarich" {
  name        = "Dawarich"
  subdomain   = "tracks"
  domain_id   = local.domain_ids["sylvain.cloud"]
  protocol    = "tcp"
  sso         = true
  apply_rules = true

  # Optional+computed: pinned so a plan can disagree with the API. See
  # resource_defaults.tf.
  mode                    = local.resource_pins.mode
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

resource "pangolin_resource_role" "dawarich" {
  resource_id = pangolin_resource.dawarich.id
  role_id     = pangolin_role.apps["dawarich"].id
}

# Created by hand in the Pangolin UI and declared here so LIVE and code agree.
# Same pattern as `pangolin_resource_rule.immich_home_ip`: the home connection
# is allowed in by IP regardless of the geo rules.
#
# Priority 9: the last slot before the `PASS COUNTRY` rules generated in
# rules.tf (FR at 10, DE at 11). It used to sit at 12, just behind them, where
# it was never reached: the home connection is French, so the FR PASS matched
# first and sent it to the SSO wall like anybody else. Ahead of the country
# rules it does what it says - the home connection gets in by IP, without
# SSO. Only the backslash DROP of rules.tf (priority 1) comes before it.
resource "pangolin_resource_rule" "dawarich_home_ip" {
  resource_id = pangolin_resource.dawarich.id
  action      = "ACCEPT"
  match       = "IP"
  value       = local.home_ip
  priority    = 9
  enabled     = true
}

# Public share links, opened worldwide without SSO through
# local.path_bypasses (rules.tf). Read off Dawarich 1.15.3 (config/routes.rb,
# app/controllers/shared/*, app/controllers/api/v1/shared/*):
#
# - Shared links (trip, track, timeline, live map), `/s/<uuid>`: random UUID,
#   expiry, revocation, optional magic phrase (POST /s/<uuid>/unlock sets an
#   encrypted cookie). Family-only links require a logged-in user anyway.
#   Their viewer calls /api/v1/shared/<uuid>/{trip,points,route,photos,...},
#   and a live link opens the ActionCable socket on /cable, which accepts a
#   connection without a session only for a valid live share
#   (app/channels/application_cable/connection.rb). It also accepts the
#   logged-in user's Rails session cookie, and so does
#   /api/v1/maps/hexagons an API key: whoever holds one of those now reaches
#   these two endpoints from any country without the SSO in front. Both are
#   already full credentials for the account, and only these two endpoints
#   answer them without the SSO - the rest of the app and of /api/v1 stays
#   behind it.
# - Shared month stats, achievements and yearly digest, `/shared/...`: their
#   `sharing_uuid` plus `public_accessible?`. The month page draws its map from
#   /api/v1/maps/hexagons, which skips the API key only when a sharing uuid is
#   given (hexagons_controller.rb).
#
# Rails serves its own static files; map tiles come from an external host.
# Not opened: the ingestion APIs (Overland, OwnTracks... - they get in from
# home through dawarich_home_ip), the rest of /api/v1 (auth/login, register,
# users/exist) and family invitations (they need an account).
locals {
  dawarich_share_paths = {
    "/s/*"                  = 4
    "/api/v1/shared/*"      = 4
    "/cable"                = 4
    "/shared/*"             = 4
    "/api/v1/maps/hexagons" = 4
    "/assets/*"             = 4
    "/maps_maplibre/*"      = 4
    "/site.webmanifest"     = 4
    "/favicon.ico"          = 4
  }
}

resource "pangolin_target" "dawarich" {
  resource_id = pangolin_resource.dawarich.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "dawarich-app"
  port        = 3000
  method      = "http"

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_port                = 3000
  hc_hostname            = "dawarich-app"
  hc_path                = "/api/v1/health"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_access_token" "dawarich" {
  resource_id = pangolin_resource.dawarich.id
  title       = "Healthcheck ${pangolin_resource.dawarich.name}"
}

output "dawarich_access_token" {
  description = "DAWARICH - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.dawarich.id,
    token = pangolin_resource_access_token.dawarich.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http_keyword" "dawarich" {
  name = "Healthcheck ${pangolin_resource.dawarich.name}"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent          = uptimekuma_monitor_group.self_hosted.id
  url             = "https://${pangolin_resource.dawarich.full_domain}"
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
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.dawarich.id),
    "P-Access-Token"    = pangolin_resource_access_token.dawarich.token
  })
  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

resource "uptimekuma_monitor_push" "backup_dawarich" {
  name = "Backup ${pangolin_resource.dawarich.name}"

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

output "uptime_backup_dawarich_url" {
  description = "DAWARICH - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_dawarich.push_token}"
  sensitive   = true
}
