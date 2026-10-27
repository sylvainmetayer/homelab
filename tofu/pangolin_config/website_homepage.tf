# Resource, target and monitors: local.websites (websites.tf).
#
# Homepage (gethomepage.dev): a page of links to every public app, for the two
# of us, behind the SSO. Links only: no widget, no API key, no Docker socket,
# so nothing to back up either - the whole configuration is templated by the
# Ansible role from this repo.
locals {
  homepage_website = {
    name      = "Homepage"
    subdomain = "home"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "homepage"

    # It does not link to itself.
    homepage = null

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "homepage"
      port    = 3000
      # Answers "up" without reading any configuration. The probe's Host
      # (homepage:3000) is in HOMEPAGE_ALLOWED_HOSTS (role homepage), or the
      # route answers 400.
      hc_path = "/api/healthcheck"
    }
  }
}

# The links Homepage shows, one per entry of local.websites whose `homepage`
# field is not null: generated rather than listed in the Ansible role, so an
# app cannot be published without its link (a missing `homepage` field fails
# the plan, it is read below on every entry) nor stay linked once removed and
# the role rerun (below). The role reads this output through docker.yml
# (`homepage_websites`) and adds the links that are no public resource
# (Jellyfin, the Pangolin dashboard) from its own defaults.
#
# The page only follows this output when the role runs: a merge redeploys the
# roles whose files changed, so a new app's link appears after the next
# `docker.yml --tags homepage` (or a deploy-docker-app run with that tag),
# once this configuration is applied.
#
# Fields of `homepage`: group and description, both required; icon (a
# dashboard-icons name or an `mdi-` icon, fetched by the browser) and title
# (default: the resource name) optional.
output "homepage_links" {
  description = "HOMEPAGE - Liens du tableau de bord, un par application publique"
  value = {
    for key, website in local.websites : key => {
      name        = lookup(website.homepage, "title", website.name)
      href        = "https://${pangolin_resource.website[key].full_domain}"
      group       = website.homepage.group
      description = website.homepage.description
      icon        = lookup(website.homepage, "icon", "")
    } if website.homepage != null
  }
}

output "homepage_access_token" {
  description = "HOMEPAGE - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["homepage"]
  sensitive   = true
}
