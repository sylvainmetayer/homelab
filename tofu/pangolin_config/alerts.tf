# Alertes de Pangolin lui-même, en plus d'Uptime Kuma : un Newt déconnecté se voit
# ici tout de suite, sans attendre l'échec d'une sonde extérieure. Elles ne
# remplacent pas Uptime Kuma et son canal Telegram, seuls à couvrir ces cas :
#
# - Pangolin tombé : rien ne part, ntfy est derrière lui.
# - Site proxmox-docker hors ligne, ou coupure Internet de la maison : ntfy tourne
#   sur la VM docker, Pangolin ne le joint plus. Trois essais en quelques secondes
#   (sendAlertWebhook.ts), puis l'alerte est perdue, sans reprise.
# - Plusieurs pannes en cinq minutes : le délai est par règle, pas par site ni par
#   ressource (processAlerts.ts), et compte même si l'envoi a échoué. Seule la
#   première part, et rien ne rejoue les autres : un événement ne part qu'au
#   changement d'état. Sans délai, un site hors ligne enverrait une alerte par
#   ressource.
#
# Aucune règle de retour à la normale : il se lit dans Uptime Kuma.
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
      hostname = pangolin_site_resource.app_proxy.destination
      port     = pangolin_site_resource.app_proxy.destination_port
    }
    nas = {
      name     = "NAS"
      hostname = pangolin_site_resource.nas.destination
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

  # Mêmes cadences que les cibles (websites.tf) : sans ces seuils, le provider
  # en met 1, et un seul paquet perdu alerterait. method et follow_redirects ne
  # servent pas en tcp ; ils gardent le défaut fixe du provider, relu à l'API.
  interval            = 60
  unhealthy_interval  = 10
  timeout             = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
}

resource "pangolin_alert_rule" "ntfy" {
  for_each = local.alert_rules

  name             = each.value.name
  event_type       = each.key
  enabled          = true
  cooldown_seconds = 300

  # Une seule famille par événement : le provider refuse les autres drapeaux.
  all_sites     = each.key == "site_offline" ? true : null
  all_resources = each.key == "resource_unhealthy" ? true : null
  # Les sondes LAN seulement. all_health_checks prendrait aussi la sonde de chaque
  # cible : une panne d'appli alerterait déjà par resource_unhealthy, et elle
  # consommerait le délai de cette règle, masquant une panne de la BBOX ou du NAS.
  health_check_ids = each.key == "health_check_unhealthy" ? [for probe in pangolin_health_check.lan : probe.id] : null

  webhook_actions = [{
    url          = "https://${pangolin_resource.website["ntfy"].full_domain}/"
    auth_type    = "bearer"
    bearer_token = local.ntfy_uptime_kuma_token
    body_template = jsonencode({
      topic   = local.alert_ntfy_topic
      title   = "Pangolin : ${each.value.name}"
      message = "{{${each.value.field}}} ({{timestamp}})"
      tags    = ["warning"]
      # Comme le canal ntfy d'Uptime Kuma (website_ntfy.tf) : un son, sans passer
      # outre le mode Ne pas déranger.
      priority = 4
    })
  }]
}

# Courriel à chaque changement de santé d'une ressource : malgré son nom,
# resource_toggle suit healthy, unhealthy et degraded (resourceEvents.ts), pas
# l'activation d'une ressource. Faite à la main dans l'UI, importée (id 3, voir
# README). Elle passe par Pangolin, pas par ntfy : le site proxmox-docker hors
# ligne ne l'empêche pas, mais Pangolin tombé, rien ne part. Le délai évite un
# courriel par ressource quand un site tombe ; il vaut pour toute la règle, donc
# une seconde panne dans ces 5 minutes n'envoie rien. user_ids : le compte Admin
# destinataire, un identifiant opaque (pas d'e-mail dans ce dépôt public).
resource "pangolin_alert_rule" "resource_toggle" {
  name             = "Ressource Alerts"
  event_type       = "resource_toggle"
  enabled          = true
  cooldown_seconds = 300
  all_resources    = true
  user_ids         = ["agxy5o5qekx2nkx"]
}
