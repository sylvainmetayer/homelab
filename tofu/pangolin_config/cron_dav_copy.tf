# Copie Nextcloud vers Infomaniak (dav-copy.timer, rôle dav_copy, docker.yml),
# TEMPORAIRE : à retirer avec le rôle à la bascule des téléphones. Toutes les
# heures, la VM docker pousse up ; un down est poussé sur un code de sortie non
# nul (erreur, garde-fou de suppression, conflit) et notifie tout de suite
# (sans max_retries), le passage suivant repousse up.
#
# Trois périodes du timer sans push : la copie est morte : DOWN.
resource "uptimekuma_monitor_push" "cron_dav_copy" {
  name        = "Copie DAV : Nextcloud vers Infomaniak"
  description = "Copie à sens unique des agendas et contacts (dav-copy.timer, rôle dav_copy, temporaire). DOWN : passage en échec (erreur, garde-fou de suppression, conflit) ou copie arrêtée."

  # Not a backup: grouped with the healthchecks. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval        = 60 * 60 * 3
  retry_interval  = 60 * 10
  max_retries     = 0
  resend_interval = 0
  upside_down     = false
  active          = true
  tags            = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = local.alert_notification_ids
}

output "uptime_cron_dav_copy_url" {
  description = "VM docker - URL push de la copie DAV (rôle dav_copy, docker.yml)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_dav_copy.push_token}"
  sensitive   = true
}
