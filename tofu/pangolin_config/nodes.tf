# Looked up by name everywhere: the API lists the domains in no documented
# order, so the former `domains[0]` was whichever one Pangolin returned first.
locals {
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

# Hetzner server with no public IP, dedicated to Flip Planning (production and
# demo, ansible/flip.yml). Its newt credentials are read from this state by
# flip.yml (outputs below), not copied into secrets.sops.yaml.
resource "pangolin_site" "flip" {
  name                  = "flip"
  docker_socket_enabled = true
}

output "flip_newt_id" {
  description = "FLIP - Newt ID of the flip site, read by ansible/flip.yml"
  value       = pangolin_site.flip.newt_id
  sensitive   = true
}

output "flip_newt_secret" {
  description = "FLIP - Newt secret of the flip site, read by ansible/flip.yml"
  value       = pangolin_site.flip.newt_secret
  sensitive   = true
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

data "pangolin_domains" "all" {}
