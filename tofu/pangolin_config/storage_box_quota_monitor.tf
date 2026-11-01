# Remplissage de la Storage Box des sauvegardes, chaque lundi
# (.github/workflows/storage-box-quota.yaml) : « up » sous 80 % d'occupation
# (données et snapshots), « down » avec le pourcentage au-delà, ou si l'API
# Hetzner ne répond pas. Huit jours : un run hebdomadaire et un jour de marge
# pour un run en retard ou relancé.
resource "uptimekuma_monitor_push" "storage_box_quota" {
  name = "Storage Box"

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  interval = 60 * 60 * 24 * 8

  # A pushed down pages at once. See uptime_globals.tf.
  max_retries    = local.push_down_max_retries
  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = local.alert_notification_ids
}

# Lu par tofu/github (secret STORAGE_BOX_QUOTA_PUSH_URL de l'environnement
# storage-box-quota).
output "uptime_storage_box_quota_url" {
  description = "URL push du contrôle hebdomadaire du remplissage de la Storage Box"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.storage_box_quota.push_token}"
  sensitive   = true
}
