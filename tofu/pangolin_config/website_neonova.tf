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

  # Help site of the same project (second container of the role neonova): same
  # PIN. Its own SSO role: one per app (test one_role_per_app_slug).
  neonova_aide_website = {
    name      = "Neonova Aide"
    subdomain = "aide-neonova"
    domain_id = local.domain_ids["sylvain.dev"]
    role      = "neonova-aide"

    homepage = {
      group       = "Divers"
      description = "Fiches pratiques de Neonova"
      icon        = "mdi-help-circle-outline"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "neonova-aide"
      port    = 8080
    }
  }
}

resource "pangolin_resource_pincode" "neonova" {
  resource_id = pangolin_resource.website["neonova"].id
  pincode     = tostring(local.neonova_pin)
}

resource "pangolin_resource_pincode" "neonova_aide" {
  resource_id = pangolin_resource.website["neonova_aide"].id
  pincode     = tostring(local.neonova_pin)
}
