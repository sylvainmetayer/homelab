# Resource, target and monitors: local.websites (websites.tf). No backup
# monitor.
#
# Its nginx proxies /api/ to Immich with a server-side API key
# (immich-swipe.conf.j2, immich role): whoever passes the SSO acts on the
# photo library with that key. Its own role, not Immich's: a member of the
# `immich` role is no longer let in by that alone. Members are added in the
# Pangolin UI (Sylvain).
locals {
  immich_swipe_website = {
    name      = "Immich Swipe"
    subdomain = "swipe-photos"
    domain_id = local.domain_ids["sylvain.cloud"]

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Photos et médias"
      description = "Trier les photos d'Immich par balayage"
      icon        = "immich"
    }

    role = "immich-swipe"

    target = {
      site_id = pangolin_site.pi.id
      ip      = "immich-swipe"
      port    = 80
    }
  }
}
