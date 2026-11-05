# Resource, target and monitors: local.websites (websites.tf). No backup
# monitor (nothing persisted).
#
# Immich Power Tools has no login of its own once IMMICH_API_KEY is set
# (immich role): whoever passes the SSO acts on the photo library with that
# key, and /api/immich-proxy relays any Immich API call. Its own role,
# `immich-power-tools`, created with no member: Sylvain alone adds himself in
# the Pangolin UI. No path opened, no home-IP rule. Like every entry it still
# gets the healthcheck access token (websites.tf), held by the Uptime Kuma
# monitor: whoever holds it passes the SSO and acts on the library with the key.
locals {
  immich_power_tools_website = {
    name      = "Immich Power Tools"
    subdomain = "power-tools"
    domain_id = local.domain_ids["sylvain.cloud"]

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Photos et médias"
      description = "Gérer les personnes, lieux, dates et albums d'Immich en masse"
      icon        = "immich"
    }

    role = "immich-power-tools"

    target = {
      site_id = pangolin_site.pi.id
      ip      = "immich-power-tools"
      port    = 3000
      # The image's own healthcheck: {"status":"healthy"}, no database call.
      hc_path = "/api/health"
    }
  }
}
