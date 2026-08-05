
output "domains" {
  value = data.pangolin_domains.all.domains
}

resource "pangolin_site_resource" "app_proxy" {
  site_id = pangolin_site.proxmox_lxc.id
  name    = "BBOX"
  mode    = "http"
  # TODO How to handle TLS ?
  # ssl = true
  domain_id        = local.main_domain_id
  subdomain        = "bbox-internal"
  destination      = "192.168.1.254"
  scheme           = "http"
  destination_port = 80
}

# These two already existed on the live server (created outside of Tofu) -
# adopted here via `tofu import` so the OLM-client access grants below can
# reference them. Both are raw L4 tunnels off the proxmox-lxc site's Newt
# agent (which has LAN visibility), not off the docker/pi sites themselves -
# same pattern as the BBOX resource above.
resource "pangolin_site_resource" "docker_apps" {
  site_id        = pangolin_site.proxmox_lxc.id
  name           = "Docker Apps"
  mode           = "host"
  alias          = "docker-apps.internal"
  destination    = "192.168.1.216"
  disable_icmp   = true
  tcp_port_range = "22"
  udp_port_range = "*"
}

resource "pangolin_site_resource" "pi" {
  site_id        = pangolin_site.proxmox_lxc.id
  name           = "Raspberry PI"
  mode           = "host"
  alias          = "pi.internal"
  destination    = "192.168.1.96"
  disable_icmp   = false
  tcp_port_range = "*"
  udp_port_range = "*"
}

# Pangolin denies DNS resolution / access to a private site resource unless
# the connecting OLM client is explicitly granted it - a missing grant here
# is why the CI runner's OLM tunnel can resolve one of these aliases but not
# the other. client_id is the CI's OLM client (the one identified by the
# OLM_ID/OLM_SECRET GitHub Actions secrets).
resource "pangolin_site_resource_client" "docker_apps_ci" {
  client_id        = var.ci_olm_client_id
  site_resource_id = pangolin_site_resource.docker_apps.id
}

resource "pangolin_site_resource_client" "pi_ci" {
  client_id        = var.ci_olm_client_id
  site_resource_id = pangolin_site_resource.pi.id
}
