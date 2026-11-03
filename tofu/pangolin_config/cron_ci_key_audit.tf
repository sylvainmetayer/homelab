# Contrôle de la clé SSH de la CI (ci-key-audit.timer, rôle ci_key_audit,
# docker.yml). Toutes les 10 minutes, la VM docker compare les connexions de la
# clé aux runs GitHub du déploiement et pousse up.
#
# Trois périodes du timer sans push : le contrôle est mort, ou n'arrive plus à
# conclure (VictoriaLogs, API GitHub, journal d'un hôte) : DOWN. Sans
# max_retries : un down poussé (connexion hors run, ntfy tombé) notifie tout de
# suite, Telegram compris ; le passage suivant repousse up.
resource "uptimekuma_monitor_push" "cron_ci_key_audit" {
  name        = "Clé de CI : contrôle"
  description = "Connexions de la clé SSH de la CI comparées aux runs GitHub (ci-key-audit.timer, rôle ci_key_audit). DOWN : connexion hors déploiement, ou contrôle sans conclusion."

  # Not a backup: grouped with the healthchecks. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval        = 60 * 30
  retry_interval  = 60 * 10
  max_retries     = 0
  resend_interval = 0
  upside_down     = false
  active          = true
  tags            = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = local.alert_notification_ids
}

output "uptime_cron_ci_key_audit_url" {
  description = "VM docker - URL push du contrôle de la clé de CI (rôle ci_key_audit, docker.yml)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_ci_key_audit.push_token}"
  sensitive   = true
}
