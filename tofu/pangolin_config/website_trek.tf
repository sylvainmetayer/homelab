resource "pangolin_resource" "trek" {
  name        = "TREK"
  subdomain   = "travels"
  domain_id   = local.domain_ids["sylvain.cloud"]
  protocol    = "tcp"
  sso         = true
  apply_rules = true
}

resource "pangolin_resource_role" "trek" {
  resource_id = pangolin_resource.trek.id
  role_id     = pangolin_role.apps["trek"].id
}

resource "pangolin_target" "trek" {
  resource_id = pangolin_resource.trek.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "trek"
  port        = 3000
  method      = "http"

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_port                = 3000
  hc_hostname            = "trek"
  hc_path                = "/api/health"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_access_token" "trek" {
  resource_id = pangolin_resource.trek.id
  title       = "Healthcheck ${pangolin_resource.trek.name}"
}

output "trek_access_token" {
  description = "TREK - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.trek.id,
    token = pangolin_resource_access_token.trek.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "trek" {
  name            = "Healthcheck ${pangolin_resource.trek.name}"
  url             = "https://${pangolin_resource.trek.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.trek.id),
    "P-Access-Token"    = pangolin_resource_access_token.trek.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

resource "uptimekuma_monitor_push" "backup_trek" {
  name = "Backup ${pangolin_resource.trek.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

output "uptime_backup_trek_url" {
  description = "TREK - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_trek.push_token}"
  sensitive   = true
}
