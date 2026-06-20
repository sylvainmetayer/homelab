resource "pangolin_resource" "monica" {
  name      = "Monica CRM"
  subdomain = "crm"
  domain_id = local.domain_ids["sylvain.dev"]
  protocol  = "tcp"
  sso       = true
  apply_rules = true
}

resource "pangolin_resource_role" "monica" {
  resource_id = pangolin_resource.monica.id
  role_id     = pangolin_role.apps["monica"].id
}

resource "pangolin_target" "monica" {
  resource_id = pangolin_resource.monica.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "monica_v4"
  port        = 80
  method      = "http"

  hc_enabled             = true
  hc_path                = "/"
  hc_method              = "GET"
  hc_status              = 200
  hc_headers             = []
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_access_token" "monica" {
  resource_id = pangolin_resource.monica.id
  title       = "Healthcheck ${pangolin_resource.monica.name}"
}

output "monica_access_token" {
  description = "MONICA - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.monica.id,
    token = pangolin_resource_access_token.monica.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "monica" {
  name            = "Healthcheck ${pangolin_resource.monica.name}"
  url             = "https://${pangolin_resource.monica.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.monica.id),
    "P-Access-Token"    = pangolin_resource_access_token.monica.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_monica" {
  name = "Backup ${pangolin_resource.monica.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

resource "uptimekuma_monitor_push" "cron_monica" {
  name = "Cron ${pangolin_resource.monica.name}"

  interval = 60 * 15

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

output "uptime_backup_monica_url" {
  description = "MONICA - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_monica.push_token}"
  sensitive   = true
}

output "uptime_cron_monica_url" {
  description = "MONICA - URL pour envoyer les heartbeats push du cron"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_monica.push_token}"
  sensitive   = true
}
