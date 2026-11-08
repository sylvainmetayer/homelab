# Support à distance (POC du 06/11/2026) : prendre la main sur un PC depuis un
# navigateur, par une ressource publique Pangolin `vnc` ou `rdp` (client web
# servi par Pangolin, pont WebSocket fait par le Newt du site, paquet
# browsergateway). Newt tourne sur le PC lui-même (ansible/pc-support.yml) et
# vise la boucle locale : le PC n'ouvre aucun port.
#
# Hors de local.websites, exprès : chaque entrée y reçoit une sonde HTTP, un
# jeton d'accès et un moniteur Uptime Kuma, qui alerteraient dès que le PC est
# éteint. Ce qui reste commun y est rebranché à la main : règles FR/DE et audits
# (local.managed_resources, local.declared_target_ids, rules.tf), rôle
# (local.declared_role_ids, access_inventory.tf), groupe Pocket ID
# (local.pocket_id_role_groups, pocket_id.tf). Le site n'est pas dans l'alerte
# « Site hors ligne » (local.alert_infra_sites, alerts.tf).
#
# Sous-domaines neutres et aléatoires : les journaux Certificate Transparency
# sont publics, le nom ne doit pas dire qu'il y a un bureau derrière.
locals {
  remote_desktops = {
    # Partage de la session ouverte (gnome-remote-desktop, service utilisateur),
    # par le relais local de pc-support.yml : grd n'offre que le TLS anonyme,
    # que le client VNC du navigateur ne négocie pas.
    pc_sylvain_vnc = {
      name      = "PC Sylvain (VNC)"
      mode      = "vnc"
      subdomain = "d-tyl53u"
      site_id   = pangolin_site.pc_sylvain.id
      port      = 5901
    }
    # Connexion à distance dès le boot, écran de connexion GDM
    # (gnome-remote-desktop, service système).
    pc_sylvain_rdp = {
      name      = "PC Sylvain (RDP)"
      mode      = "rdp"
      subdomain = "d-nb335s"
      site_id   = pangolin_site.pc_sylvain.id
      port      = 3389
    }
  }
}

# Le poste de Sylvain (Fedora). Identifiants Newt lus dans ce state par
# ansible/pc-support.yml (outputs ci-dessous). docker_socket_enabled : même
# remarque que proxmox_lxc (nodes.tf), Pangolin le met à true à la création.
resource "pangolin_site" "pc_sylvain" {
  name                  = "pc-sylvain"
  docker_socket_enabled = true
}

output "pc_sylvain_newt_id" {
  description = "PC SYLVAIN - Newt ID of the pc-sylvain site, read by ansible/pc-support.yml"
  value       = pangolin_site.pc_sylvain.newt_id
  sensitive   = true
}

output "pc_sylvain_newt_secret" {
  description = "PC SYLVAIN - Newt secret of the pc-sylvain site, read by ansible/pc-support.yml"
  value       = pangolin_site.pc_sylvain.newt_secret
  sensitive   = true
}

resource "pangolin_resource" "remote_desktop" {
  for_each = local.remote_desktops

  name        = each.value.name
  mode        = each.value.mode
  subdomain   = each.value.subdomain
  domain_id   = local.domain_ids["sylvain.cloud"]
  sso         = true
  apply_rules = true

  # Mêmes épingles que pangolin_resource.website (resource_defaults.tf), sauf
  # `mode`, propre à chaque entrée.
  ssl                     = local.resource_pins.ssl
  enabled                 = local.resource_pins.enabled
  block_access            = local.resource_pins.block_access
  email_whitelist_enabled = local.resource_pins.email_whitelist_enabled
  sticky_session          = local.resource_pins.sticky_session
  resource_policy_id      = local.resource_pins.resource_policy_id

  maintenance_mode_enabled = local.maintenance.enabled
  maintenance_mode_type    = local.maintenance.type
  maintenance_title        = local.maintenance.title
  maintenance_message      = local.maintenance.message
}

# Sonde coupée : le PC est souvent éteint, une sonde ne ferait que basculer la
# santé de la ressource (et les alertes resource_unhealthy, resource_toggle).
# Les autres champs hc_* restent épinglés (optional+computed, AGENTS.md).
resource "pangolin_target" "remote_desktop" {
  for_each = local.remote_desktops

  resource_id = pangolin_resource.remote_desktop[each.key].id
  site_id     = each.value.site_id
  ip          = "127.0.0.1"
  port        = each.value.port
  method      = "http"

  hc_enabled             = false
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_port                = each.value.port
  hc_hostname            = "127.0.0.1"
  hc_path                = "/"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 60
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

# Qui prend la main : les membres du groupe Pocket ID « support » (Sylvain seul
# pour le POC), rôle réécrit à chaque connexion (pangolin_idp, pocket_id.tf).
resource "pangolin_role" "support" {
  name                    = "support"
  description             = "Role for the remote desktop resources (remote_support.tf)"
  allow_ssh               = local.role_pins.allow_ssh
  ssh_sudo_mode           = local.role_pins.ssh_sudo_mode
  ssh_sudo_commands       = local.role_pins.ssh_sudo_commands
  ssh_create_home_dir     = local.role_pins.ssh_create_home_dir
  ssh_unix_groups         = local.role_pins.ssh_unix_groups
  require_device_approval = local.role_pins.require_device_approval
}

resource "pangolin_resource_role" "remote_desktop" {
  for_each = local.remote_desktops

  resource_id = pangolin_resource.remote_desktop[each.key].id
  role_id     = pangolin_role.support.id
}
