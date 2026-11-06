# Resource, target and monitors: local.websites (websites.tf). No backup
# monitor (nothing persisted).
#
# Immich Power Tools: each person signs in with their own Immich account
# (OAuth through Immich, hence Pocket ID; no IMMICH_API_KEY since
# 2026-11-06, immich role). Its own role, `immich-power-tools`, given by the
# Pocket ID group of the same name (the household). No path opened, no
# home-IP rule. The healthcheck access token (websites.tf) passes the SSO but
# grants nothing on the photo library: without an Immich session the app acts
# on nothing.
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
