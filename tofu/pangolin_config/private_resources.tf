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

# L'imprimante (interface web), par un client Pangolin. Faite à la main dans
# l'UI jusqu'au 23/10/2026, déclarée ici à la recréation du site du LXC.
# `ssl` n'est que calculé par le provider : HTTPS se règle dans l'UI.
resource "pangolin_site_resource" "printer" {
  site_id          = pangolin_site.proxmox_lxc.id
  name             = "Imprimante"
  mode             = "http"
  domain_id        = local.domain_ids["sylvain.cloud"]
  subdomain        = "print"
  destination      = "192.168.1.158"
  scheme           = "http"
  destination_port = 80
  disable_icmp     = true
  tcp_port_range   = "443,80"
  auth_daemon_mode = "site"
  pam_mode         = "passthrough"
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

# Proxmox web UI (8006) and its SSH (22, used by tofu/proxmox's provider),
# private since they stopped being public resources (plan sécurité, 4.3):
# reached from outside only through a Pangolin client; from home, directly.
# The hypervisor carries every VM, so its UI is not worth a public URL even
# behind the SSO and the country rules.
resource "pangolin_site_resource" "proxmox" {
  site_id        = pangolin_site.proxmox_lxc.id
  name           = "Proxmox"
  mode           = "host"
  alias          = "pve.internal"
  destination    = "192.168.1.26"
  disable_icmp   = true
  tcp_port_range = "22,8006"
  udp_port_range = "*"
}

# NAS web UI, private for the same reason: https://nas.sylvain.cloud:8443, the
# NAS's Traefik (ansible/roles/nas_proxy, nas_proxy_https_port) in front of
# UGOS's nginx on 9999. The alias is the public name whose A record
# (tofu/dns/nas.tf) points at the NAS's LAN IP: one URL at home and through a
# Pangolin client, and the Let's Encrypt certificate holds on both paths
# (Traefik picks it by SNI, whatever IP it was reached on). Plain HTTP on 9999
# stays open as the fallback (Traefik down). SMB (445) too, for the
# workstation's ad hoc mounts (ansible/pc-nas.yml): with the Pangolin client
# connected, 192.168.1.137 is routed here. No binding: Admin only.
resource "pangolin_site_resource" "nas" {
  site_id        = pangolin_site.proxmox_lxc.id
  name           = "NAS"
  mode           = "host"
  alias          = "nas.sylvain.cloud"
  destination    = "192.168.1.137"
  disable_icmp   = true
  tcp_port_range = "445,8443,9999"
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
  # "*" et non "" : le provider omet une chaîne vide, Pangolin garde alors sa
  # valeur et l'apply échoue (inconsistent result). ufw sur flip ne laisse de
  # toute façon entrer que 22/tcp.
  udp_port_range = "*"
}

# Jellyfin (ansible/roles/jellyfin, sur le NAS), dehors par un client
# Pangolin, à la même adresse qu'en LAN : https://media.sylvain.cloud (en LAN
# sur le port 8443, 443 étant pris par le nginx d'UGOS ; repli
# http://192.168.1.137:8096). L'alias est le nom public dont le A (tofu/dns,
# media.tf) vise l'IP LAN du NAS : le client Pangolin le résout vers la
# ressource, et le certificat Let's Encrypt du Traefik du NAS (rôle nas_proxy)
# vaut pour les deux chemins. Servi par le Newt du NAS, qui joint ce Traefik
# par son nom de conteneur sur le réseau Docker newt qu'ils partagent : aucune
# ressource publique. TCP 443 et 8443 seuls (Jellyfin n'est plus joignable en
# direct par Pangolin) : 8443, l'entrée LAN de Traefik (nas_proxy_https_port),
# y est ouvert aussi, pour qu'une appli réglée sur https://media.sylvain.cloud:8443 à
# la maison marche encore dehors. UDP à "*" comme ailleurs (le provider ne
# sait pas envoyer une plage vide), rien n'écoute en UDP derrière Traefik.
resource "pangolin_site_resource" "jellyfin" {
  site_id        = pangolin_site.nas.id
  name           = "Jellyfin"
  mode           = "host"
  alias          = "media.sylvain.cloud"
  destination    = "nas-proxy"
  disable_icmp   = true
  tcp_port_range = "443,8443"
  udp_port_range = "*"
}

# Qui l'atteint : les membres de ce rôle (Sylvain et sa compagne, ajoutés dans
# l'UI de Pangolin : les utilisateurs ne sont pas gérés ici). Hors de
# local.apps (roles.tf), dont chaque rôle est lié à une ressource publique.
resource "pangolin_role" "jellyfin" {
  name        = "jellyfin"
  description = "Role for media.sylvain.cloud (Jellyfin, private)"
}

# Toute mise à jour d'une pangolin_site_resource efface ses liaisons : le
# provider (stackopshq/pangolin 1.6.1, SitePrivateResource.Update) envoie
# roleIds, userIds et clientIds vides, et Pangolin
# (updateSiteResource.ts) remplace alors rôles (sauf Admin), utilisateurs et
# clients. Sans replace_triggered_by la liaison reste dans le state, absente de
# Pangolin, jusqu'au plan suivant. Avec, l'apply la retire (avant l'update, la
# liaison dépendant de la ressource) puis la recrée après. Toute
# pangolin_site_resource_{role,user,client} le porte (test
# site_resource_bindings_follow_their_resource).
# Limites : si l'update échoue, la liaison est déjà retirée et l'apply s'arrête
# sans la recréer (relancer l'apply). Une liaison faite dans l'UI, sur
# n'importe quelle pangolin_site_resource de ce fichier, est effacée elle aussi
# sans que rien ne la rétablisse ni ne la signale au plan suivant : toute
# liaison voulue se déclare ici. Le refresh retire du state une liaison absente
# de Pangolin (Read par ListSiteResourceRoles/Clients) ; sans refresh
# (-refresh=false, plan enregistré périmé), son retrait échoue en 404 et
# l'apply s'arrête avant l'update.
resource "pangolin_site_resource_role" "jellyfin" {
  role_id          = pangolin_role.jellyfin.id
  site_resource_id = pangolin_site_resource.jellyfin.id

  lifecycle {
    replace_triggered_by = [pangolin_site_resource.jellyfin]
  }
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

  # Recréée à chaque mise à jour de la ressource, qui l'efface : voir
  # pangolin_site_resource_role.jellyfin.
  lifecycle {
    replace_triggered_by = [pangolin_site_resource.docker_apps]
  }
}

resource "pangolin_site_resource_client" "pi_ci" {
  client_id        = pangolin_client.ci_runner.id
  site_resource_id = pangolin_site_resource.pi.id

  # Recréée à chaque mise à jour de la ressource, qui l'efface : voir
  # pangolin_site_resource_role.jellyfin.
  lifecycle {
    replace_triggered_by = [pangolin_site_resource.pi]
  }
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
