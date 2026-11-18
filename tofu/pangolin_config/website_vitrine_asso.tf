# Resource, target and monitors: local.websites (websites.tf).
#
# Demo of the site of an association (role vitrine_asso; its name stays out of
# this public repo, the subdomain aside). The SSO lets the owner in,
# the PIN lets the other members of the association in, who have no account
# here. Static site: no backup.
locals {
  vitrine_asso_website = {
    name      = "Vitrine asso"
    subdomain = "sofitsofun"
    domain_id = local.domain_ids["sylvain.dev"]
    role      = "vitrine-asso"

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Divers"
      description = "Démo du site d'une association"
      icon        = "mdi-web"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "vitrine-asso"
      port    = 8080
    }
  }
}

resource "pangolin_resource_pincode" "vitrine_asso" {
  resource_id = pangolin_resource.website["vitrine_asso"].id
  # Write-only : le PIN n'entre ni dans le plan ni dans l'état. Il ne part vers
  # Pangolin que si pincode_wo_version change : nouveau PIN dans SOPS = version + 1.
  pincode_wo         = tostring(local.vitrine_asso_pin)
  pincode_wo_version = 1
}
