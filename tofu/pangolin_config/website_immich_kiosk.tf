# Resource, target and monitors: local.websites (websites.tf). No backup
# monitor: Kiosk is stateless (no volume).
#
# Immich Kiosk (immich role, Pi): a full-screen photo frame. It has no login
# and reads Immich with a read-only API key held by the container: the SSO
# wall is its only guard. Its own role with no member - only Pangolin admins
# get in - and not Immich's. No path bypass, no home-IP rule: the home
# connection goes through the SSO too. Its port is not published on the Pi's
# LAN (immich role): this route is its only way in.
#
# Open question: a TV with no keyboard cannot sign in to the SSO. No public
# path is opened here; see ansible/roles/immich/README.md for the options.
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
