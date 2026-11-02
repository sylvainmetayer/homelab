# Alertes de Pangolin lui-même, en plus d'Uptime Kuma : un Newt déconnecté se voit
# ici tout de suite, sans attendre l'échec d'une sonde extérieure. Elles passent
# par ntfy, donc par Pangolin : si Pangolin tombe, seules les alertes d'Uptime
# Kuma (et Telegram) restent. Pas de Telegram ici pour cette raison.
#
# Le jeton du producteur uptime-kuma sert aussi ici : écriture seule sur ce topic,
# et il est déjà dans ce state (website_ntfy.tf), donc rien de plus n'y entre.
#
# La clé API de Pangolin doit porter les actions *AlertRule et *HealthCheck.
locals {
  alert_ntfy_topic = "uptime-kuma"

  # Les champs de `data` (siteName, resourceName, healthCheckName) varient selon
  # l'événement : server/lib/alerts/events/ de Pangolin. {{data}} entier ne se
  # met pas dans une chaîne JSON, il casserait le corps (renderTemplate).
  alert_rules = {
    site_offline = {
      name  = "Site hors ligne"
      field = "siteName"
    }
    resource_unhealthy = {
      name  = "Ressource en panne"
      field = "resourceName"
    }
    health_check_unhealthy = {
      name  = "Sonde en échec"
      field = "healthCheckName"
    }
  }

  # Sondes lancées par le Newt du LXC, depuis le LAN, pour ce qu'aucune sonde
  # extérieure ne joint. Pas l'imprimante : souvent éteinte, elle alerterait sans
  # raison.
  lan_probes = {
    bbox = {
      name     = "BBOX"
      hostname = "192.168.1.254"
      port     = 80
    }
    nas = {
      name     = "NAS"
      hostname = "192.168.1.137"
      port     = 443
    }
  }
}

resource "pangolin_health_check" "lan" {
  for_each = local.lan_probes

  name     = each.value.name
  site_id  = pangolin_site.proxmox_lxc.id
  enabled  = true
  mode     = "tcp"
  hostname = each.value.hostname
  port     = each.value.port
}

resource "pangolin_alert_rule" "ntfy" {
  for_each = local.alert_rules

  name             = each.value.name
  event_type       = each.key
  enabled          = true
  cooldown_seconds = 300

  # Une seule famille par événement : le provider refuse les autres drapeaux.
  all_sites         = each.key == "site_offline" ? true : null
  all_resources     = each.key == "resource_unhealthy" ? true : null
  all_health_checks = each.key == "health_check_unhealthy" ? true : null

  webhook_actions = [{
    url          = "https://${pangolin_resource.website["ntfy"].full_domain}/"
    auth_type    = "bearer"
    bearer_token = local.ntfy_uptime_kuma_token
    body_template = jsonencode({
      topic   = local.alert_ntfy_topic
      title   = "Pangolin : ${each.value.name}"
      message = "{{${each.value.field}}} ({{timestamp}})"
      tags    = ["warning"]
    })
  }]
}
