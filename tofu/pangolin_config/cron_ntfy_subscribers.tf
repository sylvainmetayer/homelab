# Alerte « aucun abonné » de ntfy (ntfy-subscribers-check.timer, rôle ntfy,
# docker.yml). Le 2026-10-29, un topic retiré a fait refuser (403)
# l'abonnement de l'appli : plus aucune notification sur les téléphones
# pendant 13 heures, sans alerte, le healthcheck de ntfy restant vert. Toutes
# les 10 minutes, la VM docker relit les 8 dernières heures des relevés
# « Server stats » de ntfy et pousse up si un relevé compte au moins un
# abonné, down sinon.
#
# Trois périodes du timer : deux vérifications manquées passent, pas trois.
# Un down poussé passe d'abord en PENDING (max_retries) : l'alerte tombe au
# second, un peu plus de 8 h après le départ du dernier abonné, et un relevé
# absent juste après un redémarrage de ntfy n'alerte pas. Telegram compris
# (local.alert_notification_ids) : c'est lui qui prévient quand ntfy ne joint
# plus les téléphones.
resource "uptimekuma_monitor_push" "cron_ntfy_subscribers" {
  name        = "ntfy : abonnés"
  description = "Au moins un abonné à ntfy sur 8 h (ntfy-subscribers-check.timer, rôle ntfy) : sinon, les téléphones ne reçoivent plus rien."

  # Not a backup: grouped with the healthchecks. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval        = 60 * 30
  retry_interval  = 60 * 10
  max_retries     = 1
  resend_interval = 0
  upside_down     = false
  active          = true
  tags            = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = local.alert_notification_ids
}

output "uptime_cron_ntfy_subscribers_url" {
  description = "VM docker - URL push de l'alerte « aucun abonné » de ntfy (rôle ntfy, docker.yml)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_ntfy_subscribers.push_token}"
  sensitive   = true
}
