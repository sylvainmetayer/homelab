# Resource, target and monitors: local.websites (websites.tf). No backup
# monitor of its own: its timelapse_config and timelapse_output folders are in
# Immich's archive (immich role), watched by "Backup Immich".
#
# The app has no login and holds an Immich API key: the SSO wall is its only
# guard. Its own role, with no member - only Pangolin admins get in. No path
# bypass, no home-IP rule: the home connection goes through the SSO too. Its
# port is no longer published on the Pi's LAN (immich role): this route is its
# only way in.
locals {
  immich_selfie_timelapse_website = {
    name      = "Immich Selfie Timelapse"
    subdomain = "timelapse"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "immich-selfie-timelapse"

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Photos et médias"
      description = "Timelapse des selfies d'Immich"
      icon        = "immich"
    }

    target = {
      site_id = pangolin_site.pi.id
      ip      = "immich-selfie-timelapse"
      port    = 5000
    }
  }
}
