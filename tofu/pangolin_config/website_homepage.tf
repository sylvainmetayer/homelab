# Resource, target and monitors: local.websites (websites.tf).
#
# Homepage (gethomepage.dev): a page of links to every public app, for the two
# of us, behind the SSO. Links and read-only widgets (ansible/roles/homepage),
# no Docker socket, nothing to back up - the whole configuration is templated
# by the Ansible role from this repo.
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
# (default: the resource name) and path (appended to the resource URL, default
# none: ntfy's web app lives under /app) optional. An app paused with `enabled = false`
# (docs/runbooks/app-en-pause.md) has no link while it is paused.
#
# Each link also carries the app's address as Pangolin's target reaches it,
# for the role's widgets and its up/down dot (siteMonitor): `internal_url`
# (http://<container>:<port>) and `site_monitor` (the same plus the target's
# probe path: what Pangolin's healthcheck requests, with the same Host). Only
# for targets on the Docker VM's site, where Homepage sits on the same newt
# network and resolves the container by name; empty elsewhere (the Pi, flip):
# the role sets its own LAN address for the Pi's Immich, published there, and
# flip's apps get no dot.
locals {
  homepage_internal_targets = {
    for key, website in local.websites : key => (
      # Read off the target itself, so the dot requests exactly what
      # Pangolin's probe does, defaults included (websites.tf).
      try(website.target.site_id == pangolin_site.proxmox_docker.id, false)
      ? {
        internal_url = "http://${pangolin_target.website[key].ip}:${pangolin_target.website[key].port}"
        site_monitor = "http://${pangolin_target.website[key].hc_hostname}:${pangolin_target.website[key].hc_port}${pangolin_target.website[key].hc_path}"
      }
      : { internal_url = "", site_monitor = "" }
    )
  }
}

output "homepage_links" {
  description = "HOMEPAGE - Liens du tableau de bord, un par application publique"
  value = {
    for key, website in local.websites : key => {
      name         = lookup(website.homepage, "title", website.name)
      href         = "https://${pangolin_resource.website[key].full_domain}${lookup(website.homepage, "path", "")}"
      group        = website.homepage.group
      description  = website.homepage.description
      icon         = lookup(website.homepage, "icon", "")
      internal_url = local.homepage_internal_targets[key].internal_url
      site_monitor = local.homepage_internal_targets[key].site_monitor
    } if website.homepage != null && lookup(website, "enabled", true)
  }
}

# The organisation the Pangolin widget of Homepage lists (sites, resources),
# read by docker.yml. An identifier, not a secret: kept in SOPS next to the
# provider's credentials, and already in this state (the URLs of the
# data.http audits carry it).
output "homepage_pangolin_org" {
  description = "HOMEPAGE - Organisation Pangolin du widget Pangolin"
  value       = nonsensitive(local.pangolin_org_id)
}
