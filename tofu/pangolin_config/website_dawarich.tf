# Resource, target and monitors: local.websites (websites.tf).
locals {
  dawarich_website = {
    name      = "Dawarich"
    subdomain = "tracks"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "dawarich"
    backup    = true

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "dawarich-app"
      port    = 3000
      hc_path = "/api/v1/health"
    }
  }
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
  resource_id = pangolin_resource.website["dawarich"].id
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

output "dawarich_access_token" {
  description = "DAWARICH - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["dawarich"]
  sensitive   = true
}

output "uptime_backup_dawarich_url" {
  description = "DAWARICH - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["dawarich"]
  sensitive   = true
}
