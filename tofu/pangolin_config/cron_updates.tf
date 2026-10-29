# Vérificateur des mises à jour en attente de l'hôte Proxmox VE (rôle
# update_notify, pve.yml), qui publie sur ntfy (topic scripts). Il pousse ici
# à chaque passage hebdomadaire : up avec un résumé, down si apt-get ou ntfy
# échouent. Sans battement (timer arrêté, hôte éteint), le moniteur passe au
# rouge : un vérificateur mort se voit, alors que son silence sur ntfy
# passerait pour « rien à signaler ».
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

  notification_ids = local.alert_notification_ids
}

output "uptime_cron_pve_updates_url" {
  description = "Proxmox - URL push du vérificateur des mises à jour en attente (update_notify)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_pve_updates.push_token}"
  sensitive   = true
}
