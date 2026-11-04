# Resource, target and monitors: local.websites (websites.tf).
#
# Demo of the future Neonova site (role neonova). The SSO lets the owner in, the
# PIN lets the client in, who has no account here. Static site: no backup.
locals {
  neonova_website = {
    name      = "Neonova"
    subdomain = "neonova"
    domain_id = local.domain_ids["sylvain.dev"]
    role      = "neonova"

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Divers"
      description = "Démo du futur site de Neonova"
      icon        = "mdi-web"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "neonova"
      port    = 8080
    }
  }
}

resource "pangolin_resource_pincode" "neonova" {
  resource_id = pangolin_resource.website["neonova"].id
  pincode     = tostring(local.neonova_pin)
}
