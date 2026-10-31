# Resource, target and monitors: local.websites (websites.tf). No backup
# monitor.
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

    # Bound to Immich's role, not to one of its own.
    role = "immich"

    target = {
      site_id = pangolin_site.pi.id
      ip      = "immich-swipe"
      port    = 80
    }
  }
}
