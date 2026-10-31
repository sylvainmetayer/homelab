# Sauvegarde de Jellyfin, sur le NAS (nas.yml, borgmatic en conteneur). Pas
# d'entrée dans local.websites : Jellyfin n'est pas une ressource publique
# (media.sylvain.cloud est une ressource privée, private_resources.tf), donc
# un moniteur à part, comme celui de Pangolin (website_pangolin.tf).
resource "uptimekuma_monitor_push" "backup_jellyfin" {
  name = "Backup Jellyfin"

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  interval = local.backup_push_interval

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = local.alert_notification_ids
}

output "uptime_backup_jellyfin_url" {
  description = "JELLYFIN (NAS) - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_jellyfin.push_token}"
  sensitive   = true
}
