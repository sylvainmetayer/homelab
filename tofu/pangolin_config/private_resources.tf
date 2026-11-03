# `site_ids`, `ssl` et `enabled` sont optional+computed : déclarés partout pour
# qu'un changement dans l'UI se voie au plan. Restent non déclarés : `nice_id`
# (une étiquette), `auth_daemon_port` et `pam_mode` (mode ssh seulement),
# `ai_provider_ids` (mode inference), `udp_port_range` en mode http (sans effet,
# Pangolin y force ""). `scheme`, `domain_id`, `subdomain` et `destination_port`
# valent null hors mode http : un null ne s'épingle pas.
resource "pangolin_site_resource" "app_proxy" {
  site_ids         = [pangolin_site.proxmox_lxc.id]
  name             = "BBOX"
  mode             = "http"
  domain_id        = local.domain_ids["sylvain.cloud"]
  subdomain        = "bbox-internal"
  destination      = "192.168.1.254"
  scheme           = "http"
  destination_port = 80
  disable_icmp     = true
  tcp_port_range   = "443,80"
  ssl              = true
  enabled          = true
}

# Port 9999 du NAS, fait à la main dans l'UI, importé (id 11, voir README).
# Son nom vient de l'UI ; le NAS au sens hôte est pangolin_site_resource.nas.
# Aucune liaison : Admin seul (lu à l'API le 03/11/2026).
resource "pangolin_site_resource" "nas_web" {
  site_ids = [
    pangolin_site.proxmox_docker.id,
    pangolin_site.pi.id,
    pangolin_site.proxmox_lxc.id,
  ]
  name             = "00-NTF-nas"
  mode             = "http"
  domain_id        = local.domain_ids["sylvain.cloud"]
  subdomain        = "nas-internal"
  destination      = pangolin_site_resource.nas.destination
  scheme           = "http"
  destination_port = 9999
  disable_icmp     = true
  tcp_port_range   = "443,80"
  auth_daemon_mode = "site"
  pam_mode         = "passthrough"
  ssl              = true
  enabled          = true
}

# L'imprimante (interface web), par un client Pangolin. Faite à la main dans
# l'UI jusqu'au 23/10/2026, déclarée ici à la recréation du site du LXC.
resource "pangolin_site_resource" "printer" {
  site_ids         = [pangolin_site.proxmox_lxc.id]
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
  ssl              = true
  enabled          = true
}

resource "pangolin_site_resource" "docker_apps" {
  site_ids       = [pangolin_site.proxmox_lxc.id]
  name           = "Docker Apps"
  mode           = "host"
  alias          = "docker-apps.internal"
  destination    = "192.168.1.216"
  disable_icmp   = true
  tcp_port_range = "22"
  udp_port_range = "*"
  ssl            = false
  enabled        = true
}

resource "pangolin_site_resource" "pi" {
  site_ids       = [pangolin_site.proxmox_lxc.id]
  name           = "Raspberry PI"
  mode           = "host"
  alias          = "pi.internal"
  destination    = "192.168.1.96"
  disable_icmp   = false
  tcp_port_range = "22"
  udp_port_range = "*"
  ssl            = false
  enabled        = true
}

# Proxmox web UI (8006) and its SSH (22, used by tofu/proxmox's provider),
# private since they stopped being public resources (plan sécurité, 4.3):
# reached from outside only through a Pangolin client; from home, directly.
# The hypervisor carries every VM, so its UI is not worth a public URL even
# behind the SSO and the country rules.
resource "pangolin_site_resource" "proxmox" {
  site_ids       = [pangolin_site.proxmox_lxc.id]
  name           = "Proxmox"
  mode           = "host"
  alias          = "pve.internal"
  destination    = "192.168.1.26"
  disable_icmp   = true
  tcp_port_range = "22,8006"
  udp_port_range = "*"
  ssl            = false
  enabled        = true
}

# NAS web UI, private for the same reason: https://nas.sylvain.cloud, the
# NAS's Traefik (ansible/roles/nas_proxy) in front of UGOS's nginx on 9999, on
# the host's 443 (its relay, nas_proxy_host_https_port, once UGOS's HTTPS
# redirect is unticked) and on 8443 (nas_proxy_https_port, published by
# Docker, which keeps working if UGOS's nginx takes 443 back). The alias is the public name whose A record
# (tofu/dns/nas.tf) points at the NAS's LAN IP: one URL at home and through a
# Pangolin client, and the Let's Encrypt certificate holds on both paths
# (Traefik picks it by SNI, whatever IP it was reached on). Plain HTTP on 9999
# stays open as the fallback (Traefik down), by IP only:
# http://192.168.1.137:9999 (the name carries HSTS, so
# http://nas.sylvain.cloud:9999 is upgraded). SMB (445) too, for the
# workstation's ad hoc mounts (ansible/pc-nas.yml): with the Pangolin client
# connected, 192.168.1.137 is routed here. SSH (22) as well, to administer
# the NAS from outside (2026-10-31). The NAS sees every client as the newt
# LXC (192.168.1.200): its auth logs lose the client IP, and a UGOS IP block
# on failed logins would cut every client's access (UI, SMB, SSH) until
# unblocked from the LAN. No NFS: UGOS serves NFSv3 only (rpcbind 111 and a
# dynamic mountd port), and its exports only accept the docker VM and the
# Proxmox host; opening them to the LXC would give root on them to every
# client. No binding: Admin only.
resource "pangolin_site_resource" "nas" {
  site_ids       = [pangolin_site.proxmox_lxc.id]
  name           = "NAS"
  mode           = "host"
  alias          = "nas.sylvain.cloud"
  destination    = "192.168.1.137"
  disable_icmp   = true
  tcp_port_range = "22,443,445,8443,9999"
  udp_port_range = "*"
  ssl            = false
  enabled        = true
}

# Blocky (DNS filtering, ansible/roles/blocky) on the newt LXC, for a phone on
# mobile data: in the Pangolin Android app, "Override DNS" + "Tunnel DNS" with
# 192.168.1.200 as primary upstream DNS server (the app asks for the DNS
# server to be a Pangolin resource, docs/runbooks/dns-blocky.md). The
# Pangolin server pushes no DNS setting to its clients (1.25: every field of
# buildOlmDnsConfig is undefined), hence the manual setting. Served by the
# newt of this same LXC: a restart of blocky.service never touches the tunnel.
# The Pi's Blocky, the secondary, already answers through the `pi` resource
# (UDP "*"); its TCP 53 is not opened, so only this primary takes DNS over
# TCP (large answers). No binding: Admin only, like the NAS.
resource "pangolin_site_resource" "dns" {
  site_ids       = [pangolin_site.proxmox_lxc.id]
  name           = "DNS"
  mode           = "host"
  alias          = "dns.internal"
  destination    = "192.168.1.200"
  disable_icmp   = true
  tcp_port_range = "53"
  udp_port_range = "53"
  ssl            = false
  enabled        = true
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
  site_ids       = [pangolin_site.flip.id]
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
  ssl            = false
  enabled        = true
}

# Jellyfin (ansible/roles/jellyfin, sur le NAS), dehors par un client
# Pangolin, à la même adresse qu'en LAN : https://media.sylvain.cloud (en LAN
# sur le 443 de l'hôte, tenu par le relais de nas_proxy, ou sur le 8443 ;
# repli http://192.168.1.137:8096). L'alias est le nom public dont le A (tofu/dns,
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
  site_ids       = [pangolin_site.nas.id]
  name           = "Jellyfin"
  mode           = "host"
  alias          = "media.sylvain.cloud"
  destination    = "nas-proxy"
  disable_icmp   = true
  tcp_port_range = "443,8443"
  udp_port_range = "*"
  ssl            = false
  enabled        = true
}

# Qui l'atteint : les membres de ce rôle (Sylvain et sa compagne, ajoutés dans
# l'UI de Pangolin : les utilisateurs ne sont pas gérés ici). Hors de
# local.apps (roles.tf), dont chaque rôle est lié à une ressource publique.
resource "pangolin_role" "jellyfin" {
  name                    = "jellyfin"
  description             = "Role for media.sylvain.cloud (Jellyfin, private)"
  allow_ssh               = local.role_pins.allow_ssh
  ssh_sudo_mode           = local.role_pins.ssh_sudo_mode
  ssh_sudo_commands       = local.role_pins.ssh_sudo_commands
  ssh_create_home_dir     = local.role_pins.ssh_create_home_dir
  ssh_unix_groups         = local.role_pins.ssh_unix_groups
  require_device_approval = local.role_pins.require_device_approval
}

resource "pangolin_site_resource_role" "jellyfin" {
  role_id          = pangolin_role.jellyfin.id
  site_resource_id = pangolin_site_resource.jellyfin.id
}

# MediaManager à l'essai (ansible/roles/mediamanager, sur le NAS), comme
# Jellyfin : https://mediamanager.sylvain.cloud, à la maison (443 de l'hôte,
# relais de nas_proxy, ou 8443) comme dehors par un client Pangolin. L'alias
# est le nom public dont le A (tofu/dns, mediamanager.tf) vise l'IP LAN du
# NAS ; le Traefik du NAS (rôle nas_proxy) sert le certificat Let's Encrypt
# sur les deux chemins et joint MediaManager par un réseau Docker dédié
# (mediamanager_proxy). Servi par le Newt du NAS, qui joint ce Traefik par son
# nom de conteneur sur le réseau newt : même destination et mêmes ports que
# pangolin_site_resource.jellyfin. MediaManager lui-même (8000) n'est plus sur
# newt ni joignable par Pangolin. Traefik choisit l'appli au nom (SNI, Host) :
# un membre du rôle jellyfin qui viserait l'alias media.sylvain.cloud avec ce
# nom atteindrait la page de connexion de MediaManager, comme n'importe quel
# appareil du LAN ; le compte de MediaManager reste la barrière. Ni
# qBittorrent ni Prowlarr : leurs interfaces restent sur le 127.0.0.1 du NAS
# (tunnel SSH, README du rôle). UDP à "*" comme ailleurs (le provider ne sait
# pas envoyer une plage vide), rien n'écoute en UDP derrière Traefik.
resource "pangolin_site_resource" "mediamanager" {
  site_ids       = [pangolin_site.nas.id]
  name           = "MediaManager"
  mode           = "host"
  alias          = "mediamanager.sylvain.cloud"
  destination    = "nas-proxy"
  disable_icmp   = true
  tcp_port_range = "443,8443"
  udp_port_range = "*"
  ssl            = false
  enabled        = true
}

# Qui l'atteint : les membres de ce rôle, Sylvain seul (ajouté dans l'UI de
# Pangolin : les utilisateurs ne sont pas gérés ici). Hors de local.apps
# (roles.tf), comme jellyfin.
resource "pangolin_role" "mediamanager" {
  name                    = "mediamanager"
  description             = "Role for mediamanager.sylvain.cloud (MediaManager trial on the NAS, private)"
  allow_ssh               = local.role_pins.allow_ssh
  ssh_sudo_mode           = local.role_pins.ssh_sudo_mode
  ssh_sudo_commands       = local.role_pins.ssh_sudo_commands
  ssh_create_home_dir     = local.role_pins.ssh_create_home_dir
  ssh_unix_groups         = local.role_pins.ssh_unix_groups
  require_device_approval = local.role_pins.require_device_approval
}

resource "pangolin_site_resource_role" "mediamanager" {
  role_id          = pangolin_role.mediamanager.id
  site_resource_id = pangolin_site_resource.mediamanager.id
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

# Les deux sorties VPN : une passerelle route 0.0.0.0/0 par son site, donc un
# client Pangolin qui s'y attache sort sur Internet par là. Pangolin force la
# destination, tous les ports et l'ICMP (createSiteResource.ts), le provider les
# planifie : un écart se voit au plan sans les déclarer. `alias` reste non
# déclaré, le provider le refuse dans ce mode. Faites dans l'UI, importées avec
# `tofu import` (README du module). Aucune liaison : Admin seul.
resource "pangolin_site_resource" "vpn" {
  name = "vpn"
  mode = "gateway"
  site_ids = [
    pangolin_site.proxmox_docker.id,
    pangolin_site.pi.id,
    pangolin_site.proxmox_lxc.id,
    pangolin_site.nas.id,
  ]
  ssl     = false
  enabled = true
}

resource "pangolin_site_resource" "vpn_flip" {
  name     = "vpn-flip"
  mode     = "gateway"
  site_ids = [pangolin_site.flip.id]
  ssl      = false
  enabled  = true
}
