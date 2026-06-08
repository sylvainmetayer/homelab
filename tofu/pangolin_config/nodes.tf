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

# Only to fetch node id when needed.
data "pangolin_sites" "all" {}

output "online_sites" {
  value = [for s in data.pangolin_sites.all.sites : s if s.online]
}

data "pangolin_domains" "all" {}
