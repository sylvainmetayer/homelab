# Test de restauration des sauvegardes vzdump de l'hôte Proxmox (VM docker,
# LXC newt), le 2 et le 16 du mois sur l'hôte même
# (vzdump-restore-test.timer, rôle vzdump_restore_test, pve.yml). Il pousse
# up, ou down avec la raison ; le détail part aussi sur ntfy (topic scripts).
#
# 20 jours, comme « Restore test » (restore_test_monitor.tf) : deux runs sont
# espacés de 17 jours au plus, et le provider plafonne un push à 24 jours,
# d'où deux runs par mois plutôt qu'un. Sans push (hôte éteint à l'heure dite,
# timer mort), le moniteur passe au rouge.
resource "uptimekuma_monitor_push" "cron_vzdump_restore_test" {
  name = "Test restauration vzdump"

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  interval = 60 * 60 * 24 * 20

  # A pushed down pages at once. See uptime_globals.tf.
  max_retries    = local.push_down_max_retries
  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = local.alert_notification_ids
}

output "uptime_cron_vzdump_restore_test_url" {
  description = "Proxmox - URL push du test de restauration des sauvegardes vzdump (vzdump_restore_test, pve.yml)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_vzdump_restore_test.push_token}"
  sensitive   = true
}
