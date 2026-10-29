# Copie à sens unique de kDrive vers le NAS (kdrive-sync.timer, rôle
# kdrive_sync, nas.yml), chaque nuit : le NAS pousse up avec le volume copié,
# ou down avec le code de sortie de rclone et sa dernière erreur. Pas une
# sauvegarde borg (aucun dépôt, rien dans .github/restore-test/apps.json) :
# rangé avec les healthchecks, comme « Certificats NAS ». Deux jours et une
# heure : une nuit manquée (NAS éteint) passe, pas deux.
resource "uptimekuma_monitor_push" "cron_kdrive_sync" {
  name = "kDrive vers NAS"

  # Not a backup: grouped with the healthchecks. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval = 60 * 60 * 49

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = local.alert_notification_ids
}

output "uptime_cron_kdrive_sync_url" {
  description = "NAS - URL push de la copie nocturne de kDrive (kdrive_sync)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_kdrive_sync.push_token}"
  sensitive   = true
}
