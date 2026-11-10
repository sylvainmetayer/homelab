# Sauvegarde de la configuration de l'hôte Proxmox (config.db de pmxcfs,
# réseau), pve.yml, rôle pve_config_backup. Pas une ressource Pangolin : un
# moniteur à part, comme celui de Jellyfin (backup_jellyfin.tf).
resource "uptimekuma_monitor_push" "backup_pve_config" {
  name = "Backup Proxmox config"

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

output "uptime_backup_pve_config_url" {
  description = "Proxmox - URL push de la sauvegarde de sa configuration (rôle pve_config_backup, pve.yml)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_pve_config.push_token}"
  sensitive   = true
}
