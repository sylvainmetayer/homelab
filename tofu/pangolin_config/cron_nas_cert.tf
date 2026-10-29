# Échéance des certificats du Traefik du NAS (media.sylvain.cloud,
# nas.sylvain.cloud), servis sur le LAN et par le client Pangolin seulement :
# un moniteur HTTP de cet Uptime Kuma (PikaPods) ne les joint pas. Le NAS
# vérifie lui-même chaque jour (nas-proxy-cert-check.timer, rôle nas_proxy,
# nas.yml) et pousse up, ou down avec la raison (moins de
# nas_proxy_cert_check_min_days jours, chaîne ou nom invalide, Traefik
# injoignable). Deux jours et une heure : une journée manquée (NAS éteint à
# 07:00) passe, pas deux.
resource "uptimekuma_monitor_push" "cron_nas_cert" {
  name = "Certificats NAS"

  # Not a backup: grouped with the healthchecks. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval = 60 * 60 * 49

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = local.alert_notification_ids
}

output "uptime_cron_nas_cert_url" {
  description = "NAS - URL push de la vérification d'échéance des certificats (nas_proxy)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_nas_cert.push_token}"
  sensitive   = true
}
