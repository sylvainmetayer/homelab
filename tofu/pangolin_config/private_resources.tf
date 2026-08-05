
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

# Raw L4 tunnel to the Pi's own sshd, so CI (which only has an OLM/Newt
# tunnel into the private mesh, not LAN access) can reach it as
# "pi-apps.internal:22" the same way it already reaches the docker host at
# docker-apps.internal. destination is the Pi's LAN IP (see
# ansible/inventory/hosts) since the newt container runs on a bridge
# network, not --network host.
resource "pangolin_site_resource" "pi_ssh" {
  site_id        = pangolin_site.pi.id
  name           = "Pi SSH"
  mode           = "host"
  alias          = "pi-apps.internal"
  destination    = "192.168.1.96"
  tcp_port_range = "22"
  udp_port_range = ""
}
