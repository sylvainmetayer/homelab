locals {
  main_domain_id   = data.pangolin_domains.all.domains[0].domain_id
  main_domain_name = data.pangolin_domains.all.domains[0].base_domain
  domain_ids = {
    for domain in data.pangolin_domains.all.domains :
    domain.base_domain => domain.domain_id
  }
}

resource "pangolin_site" "proxmox_lxc" {
  name                  = "proxmox-lxc"
  docker_socket_enabled = false
}

resource "pangolin_site" "proxmox_docker" {
  name                  = "proxmox-docker"
  docker_socket_enabled = true
}

resource "pangolin_site" "pi" {
  name                  = "Raspberry PI"
  docker_socket_enabled = true
}

# The Pangolin instance's own site (`type = "local"`, siteId 2). Created by the
# installer rather than by hand, and the only site that was never declared here
# - it surfaced in the August 2026 audit alongside the undeclared monitors.
#
# `type` is computed, so nothing in this block pins it to "local": the import is
# what binds it to the existing site. Applying without importing first would
# create a *second* site named "pangolin".
#
# `newt_secret` cannot be read back from the API and lands as null in state
# after an import. Harmless here - a local site has no newt connector.
resource "pangolin_site" "pangolin" {
  name                  = "pangolin"
  docker_socket_enabled = false
}

# Only to fetch node id when needed.
data "pangolin_sites" "all" {}

output "online_sites" {
  value = [for s in data.pangolin_sites.all.sites : s if s.online]
}

data "pangolin_domains" "all" {}
