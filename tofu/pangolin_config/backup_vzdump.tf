# Sauvegarde vzdump de la nuit (job de 21:00, tofu/proxmox/backup.tf : VM
# docker et LXC newt, sur le NAS). Le job ne prévient personne lui-même : son
# notification_mode renvoie au « notification-system » de Proxmox, sans cible
# déclarée dans ce dépôt. Chaque matin, vzdump-freshness.timer (rôle
# vzdump_restore_test, pve.yml) lit l'âge et la taille de la dernière archive
# de chaque invité et pousse ici : up, ou down avec l'invité en cause. Sans ce
# moniteur, un échec restait muet jusqu'au test de restauration du 2 ou du 16
# (un mois d'échecs en octobre 2026, ADR 0026).
resource "uptimekuma_monitor_push" "backup_vzdump" {
  name        = "Sauvegarde vzdump"
  description = "Dernière archive vzdump de la VM docker et du LXC newt de moins de 26 h (vzdump-freshness.timer, rôle vzdump_restore_test)."

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  interval = local.backup_push_interval

  # A missed window or a pushed `down` pages at once. See uptime_globals.tf.
  max_retries    = local.push_down_max_retries
  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = local.alert_notification_ids
}

output "uptime_backup_vzdump_url" {
  description = "Proxmox - URL push du contrôle quotidien de la sauvegarde vzdump (rôle vzdump_restore_test, pve.yml)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_vzdump.push_token}"
  sensitive   = true
}
