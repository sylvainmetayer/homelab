
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
  tcp_port_range = "22"
  udp_port_range = "*"
}

resource "pangolin_client" "ci_runner" {
  name = "ci-runner"
}

output "ci_olm_id" {
  description = "OLM ID for the CI's Tofu-managed OLM client. Consumed by tofu/github to set the OLM_ID Actions secret."
  value       = pangolin_client.ci_runner.olm_id
}

output "ci_olm_secret" {
  description = "OLM secret for the CI's Tofu-managed OLM client. Consumed by tofu/github to set the OLM_SECRET Actions secret."
  value       = pangolin_client.ci_runner.secret
  sensitive   = true
}

# Pangolin denies DNS resolution / access to a private site resource unless
# the connecting OLM client is explicitly granted it - a missing grant here
# is why the CI runner's OLM tunnel can resolve one of these aliases but not
# the other.
resource "pangolin_site_resource_client" "docker_apps_ci" {
  client_id        = pangolin_client.ci_runner.id
  site_resource_id = pangolin_site_resource.docker_apps.id
}

resource "pangolin_site_resource_client" "pi_ci" {
  client_id        = pangolin_client.ci_runner.id
  site_resource_id = pangolin_site_resource.pi.id
}
