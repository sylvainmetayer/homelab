# Alertes sur les journaux VictoriaLogs (log-alerts.timer, rôle log_alerts,
# docker.yml) : toutes les 5 minutes, la VM docker rejoue les règles (rafales de
# 5xx de Traefik, kills OOM, borgmatic muet ou en échec), alerte sur ntfy et
# pousse up ici.
#
# Trois périodes du timer sans push : le contrôle est mort, ou n'arrive plus à
# juger une règle (VictoriaLogs injoignable, ntfy qui refuse) : DOWN. Pas de down
# poussé : les alertes elles-mêmes passent par ntfy, ce moniteur ne dit que la
# cécité.
resource "uptimekuma_monitor_push" "cron_log_alerts" {
  name        = "Alertes sur les journaux"
  description = "Règles LogsQL rejouées sur VictoriaLogs (log-alerts.timer, rôle log_alerts). DOWN : contrôle mort ou sans conclusion, les alertes ne partiraient plus."

  # Not a backup: grouped with the healthchecks. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval        = 60 * 15
  retry_interval  = 60 * 5
  max_retries     = 0
  resend_interval = 0
  upside_down     = false
  active          = true
  tags            = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = local.alert_notification_ids
}

output "uptime_cron_log_alerts_url" {
  description = "VM docker - URL push des alertes sur les journaux (rôle log_alerts, docker.yml)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_log_alerts.push_token}"
  sensitive   = true
}
