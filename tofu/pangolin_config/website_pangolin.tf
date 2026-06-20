resource "uptimekuma_monitor_push" "backup_pangolin" {
  name = "Backup Pangolin"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_pangolin_url" {
  description = "PANGOLIN - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_pangolin.push_token}"
  sensitive   = true
}
