resource "uptimekuma_monitor_push" "ssh_login" {
  name = "SSH Login"

  interval = 60 * 60 * 24 * 365

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

output "uptime_ssh_login_url" {
  description = "SSH LOGIN - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.ssh_login.push_token}"
  sensitive   = true
}
