# Resource, target and monitors: local.websites (websites.tf). No backup
# monitor: Kiosk is stateless (no volume).
#
# Immich Kiosk (immich role, Pi): a full-screen photo frame. It has no login
# and reads Immich with a read-only API key held by the container: the SSO
# wall is its only guard. Its own role with no member - only Pangolin admins
# get in - and not Immich's. No path bypass. Its port is not published on the
# Pi's LAN (immich role): this route is its only way in.
#
# The TV at home cannot sign in to the SSO, so the home connection skips it
# (immich_kiosk_home_ip below). Same trade-off as immich_home_ip: every device
# behind that address sees the photo frame without login, and so would whoever
# gets the address next, until home_ip is updated and this module applied.
locals {
  immich_kiosk_website = {
    name      = "Immich Kiosk"
    subdomain = "kiosk"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "immich-kiosk"

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Photos et médias"
      description = "Cadre photo plein écran d'Immich"
      icon        = "immich"
    }

    target = {
      site_id = pangolin_site.pi.id
      ip      = "immich-kiosk"
      port    = 3000
    }
  }
}

resource "pangolin_resource_rule" "immich_kiosk_home_ip" {
  resource_id = pangolin_resource.website["immich_kiosk"].id
  action      = "ACCEPT"
  match       = "IP"
  value       = local.home_ip
  priority    = 9
  enabled     = true
}
