output "rss" {
  description = "URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.rss.push_token}"
  sensitive   = true
}
