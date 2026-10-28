# Vérificateurs des mises à jour en attente (rôle update_notify), qui publient
# sur ntfy (topic scripts) : l'hôte Proxmox VE (pve.yml, mode apt) et le NAS
# (nas.yml, mode ugos). Chacun pousse ici à chaque passage hebdomadaire : up
# avec un résumé, down si apt-get, la lecture de la version d'UGOS ou ntfy
# échouent. Sans battement (timer arrêté, hôte éteint, unité effacée par une
# réinitialisation d'UGOS), le moniteur passe au rouge : un vérificateur mort
# se voit, alors que son silence sur ntfy passerait pour « rien à signaler ».
#
# Quinze jours : un passage manqué passe, pas deux. Sous le plafond de 24
# jours des moniteurs push d'Uptime Kuma.
locals {
  update_check_push_interval = 60 * 60 * 24 * 15
}

resource "uptimekuma_monitor_push" "cron_pve_updates" {
  name = "Mises à jour Proxmox"

  # Not a backup: grouped with the healthchecks. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval = local.update_check_push_interval

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

resource "uptimekuma_monitor_push" "cron_nas_updates" {
  name = "Mises à jour NAS"

  # Not a backup: grouped with the healthchecks. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval = local.update_check_push_interval

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

output "uptime_cron_pve_updates_url" {
  description = "Proxmox - URL push du vérificateur des mises à jour en attente (update_notify)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_pve_updates.push_token}"
  sensitive   = true
}

output "uptime_cron_nas_updates_url" {
  description = "NAS - URL push du rappel des mises à jour d'UGOS (update_notify)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_nas_updates.push_token}"
  sensitive   = true
}
