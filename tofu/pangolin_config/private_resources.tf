resource "pangolin_site_resource" "app_proxy" {
  site_id = pangolin_site.proxmox_lxc.id
  name    = "BBOX"
  mode    = "http"
  # TODO How to handle TLS ?
  # ssl = true
  domain_id        = local.domain_ids["sylvain.cloud"]
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

# SSH to the flip server, which has no public IP, for manual access through a
# Pangolin client. Not for Ansible, local or CI: this resource is served by the
# newt running on flip itself, so a play that restarts newt or docker there
# would cut its own connection. Ansible goes through a ProxyJump via Pangolin
# instead (ansible/inventory/hetzner.py, .github/workflows/deploy-docker-app.yaml).
# The destination is the host's private address, reached from the newt
# container through the docker bridge. TCP 22 only: nothing else on flip is
# meant to be reached this way.
resource "pangolin_site_resource" "flip" {
  site_id        = pangolin_site.flip.id
  name           = "Flip"
  mode           = "host"
  alias          = "flip.internal"
  destination    = data.terraform_remote_state.pangolin.outputs.flip_private_ip
  disable_icmp   = true
  tcp_port_range = "22"
  udp_port_range = ""
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

# ---------------------------------------------------------------------------
# VPN exit nodes: audit only.
#
# Two site resources are in `gateway` mode, "vpn" and "vpn-flip": a gateway
# routes 0.0.0.0/0 through its site, so a Pangolin client attached to it leaves
# for the Internet from there (Pangolin forces the destination to 0.0.0.0/0, all
# TCP and UDP ports and ICMP - server/routers/siteResource/createSiteResource.ts).
#
# stackopshq/pangolin 1.6.1 cannot declare them: pangolin_site_resource
# validates `mode` against host, cidr and http only. They live in the Pangolin
# UI, which is the blind spot the rule inventory in rules.tf closed for
# hand-made rules - deleted, switched to another mode or moved to another site
# there, nothing here would notice. This reads them back and fails the plan
# instead. Once the provider supports the mode, import them as
# pangolin_site_resource and drop this block.
#
# GET /v1/org/{org}/site-resources (listAllSiteResourcesByOrg.ts) defaults to a
# page of 20 like the resources endpoint, hence pageSize and the truncation
# check. Each entry carries its `mode` and the sites of its network
# (`siteNames`, `siteIds`). The API key needs the listSiteResources action.
# ---------------------------------------------------------------------------
data "http" "pangolin_site_resources" {
  url = "${local.pangolin_url}/v1/org/${local.pangolin_org_id}/site-resources?pageSize=1000"

  request_headers = {
    Authorization = "Bearer ${local.pangolin_api_key}"
    Accept        = "application/json"
  }
}

locals {
  # Gateway name => name of the site it must route through, "" when not
  # checked. vpn-flip exits through flip, as its name says. Nothing in this
  # repository says which site "vpn" uses, so only its existence and mode are
  # checked; fill the site in once confirmed.
  vpn_gateways = {
    "vpn"      = ""
    "vpn-flip" = pangolin_site.flip.name
  }

  # Same reasoning as failed_target_lookups in rules.tf: a response that does
  # not decode is reported, not flattened into "no site resource at all".
  site_resources_unreadable = try(jsondecode(data.http.pangolin_site_resources.response_body).data.siteResources, null) == null

  live_site_resources = try(jsondecode(data.http.pangolin_site_resources.response_body).data.siteResources, [])

  # A missing or reshaped `pagination.total` counts as truncated: falling back
  # to "complete" would quietly run the audit on a partial page.
  site_resources_truncated = try(
    length(local.live_site_resources) != jsondecode(data.http.pangolin_site_resources.response_body).data.pagination.total,
    true
  )

  vpn_gateway_matches = {
    for name, site in local.vpn_gateways : name => [
      for resource in local.live_site_resources : resource
      if try(resource.name, null) == name
    ]
  }

  vpn_gateway_problems = concat(
    [for name, found in local.vpn_gateway_matches : "${name} (missing)" if length(found) == 0],
    [for name, found in local.vpn_gateway_matches : "${name} (${length(found)} site resources share this name)" if length(found) > 1],
    flatten([
      for name, found in local.vpn_gateway_matches : [
        for resource in found : "${name} (mode ${try(resource.mode, "null")}, expected gateway)"
        if try(resource.mode, null) != "gateway"
      ]
    ]),
    flatten([
      for name, found in local.vpn_gateway_matches : [
        for resource in found : "${name} (disabled)"
        if try(tobool(resource.enabled), true) == false
      ]
    ]),
    flatten([
      for name, found in local.vpn_gateway_matches : [
        for resource in found : "${name} (on site ${try(join("+", resource.siteNames), "?")}, expected ${local.vpn_gateways[name]})"
        if local.vpn_gateways[name] != "" && !contains(try(resource.siteNames, []), local.vpn_gateways[name])
      ]
    ]),
  )
}

resource "terraform_data" "vpn_gateways" {
  # Derived from the configuration, not from the live list: a site resource
  # added elsewhere must not show up as a replacement of this audit.
  input = sort(keys(local.vpn_gateways))

  lifecycle {
    precondition {
      condition = !local.site_resources_unreadable
      error_message = join(" ", [
        "Could not read the site resources (HTTP ${data.http.pangolin_site_resources.status_code}).",
        "The VPN gateway audit cannot run, so the plan is stopped rather than passing on no data.",
      ])
    }

    precondition {
      condition     = !local.site_resources_truncated
      error_message = "Pangolin returned a truncated site resource list: the VPN gateway audit could miss a gateway that still exists."
    }

    precondition {
      condition = length(local.vpn_gateway_problems) == 0
      error_message = join(" ", [
        "VPN gateway site resources not as expected:",
        "${join(", ", local.vpn_gateway_problems)}.",
        "They are made in the Pangolin UI (the provider has no `gateway` mode):",
        "recreate or fix them there, or update local.vpn_gateways if the change is intended.",
      ])
    }
  }
}
