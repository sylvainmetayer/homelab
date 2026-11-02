# Santé des applis du NAS (Jellyfin, MediaManager), servies par le Traefik du
# NAS (rôle nas_proxy) sur le LAN et par le client Pangolin seulement : un
# moniteur HTTP de cet Uptime Kuma (PikaPods) ne les joint pas. Le NAS les
# interroge lui-même toutes les 5 minutes (nas-health-check.timer, rôle
# nas_proxy, nas.yml), par son Traefik (TLS et nom compris), et pousse up, ou
# down avec la raison.
#
# Clé = nom de l'entrée de nas_proxy_health_checks (rôle nas_proxy) et suffixe
# de la sortie lue par nas.yml (uptime_health_<clé>_url). Dix minutes, deux
# périodes du timer : une fenêtre d'une seule période ferait la course avec
# chaque push. Un down poussé passe d'abord en PENDING (max_retries) : il faut
# deux vérifications en échec de suite (~5 min) pour alerter ; un NAS muet
# alerte au bout de 15 minutes (fenêtre, puis un essai). Telegram et ntfy.
#
# MediaManager est à l'essai : le retirer retire sa clé ici et sa sortie
# (ansible/roles/mediamanager/README.md, « Retirer l'essai »).
locals {
  nas_health_apps = {
    jellyfin     = "Jellyfin"
    mediamanager = "MediaManager"
  }
}

resource "uptimekuma_monitor_push" "health_nas" {
  for_each = local.nas_health_apps

  name        = "Healthcheck ${each.value}"
  description = "${each.value} sur le NAS, par son Traefik (nas-health-check.timer, rôle nas_proxy)."

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval        = 60 * 10
  retry_interval  = 60 * 5
  max_retries     = 1
  resend_interval = 0
  upside_down     = false
  active          = true
  tags            = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = local.alert_notification_ids
}

output "uptime_health_jellyfin_url" {
  description = "NAS - URL push de la santé de Jellyfin (nas_proxy)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.health_nas["jellyfin"].push_token}"
  sensitive   = true
}

output "uptime_health_mediamanager_url" {
  description = "NAS - URL push de la santé de MediaManager, à l'essai (nas_proxy)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.health_nas["mediamanager"].push_token}"
  sensitive   = true
}
