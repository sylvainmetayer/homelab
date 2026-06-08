resource "pangolin_resource" "echo" {
  name      = "Echo"
  subdomain = "echo"
  domain_id = local.domain_ids["sylvain.cloud"]
  protocol  = "tcp"
  sso       = true
  apply_rules = true
}

resource "pangolin_resource_role" "echo" {
  resource_id = pangolin_resource.echo.id
  role_id     = pangolin_role.apps["echo"].id
}

resource "pangolin_target" "echo" {
  resource_id = pangolin_resource.echo.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "echo"
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

resource "pangolin_resource_access_token" "echo" {
  resource_id = pangolin_resource.echo.id
  title       = "Healthcheck ${pangolin_resource.echo.name}"
}

output "echo_access_token" {
  description = "ECHO - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.echo.id,
    token = pangolin_resource_access_token.echo.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "echo" {
  name            = "Healthcheck ${pangolin_resource.echo.name}"
  url             = "https://${pangolin_resource.echo.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.echo.id),
    "P-Access-Token"    = pangolin_resource_access_token.echo.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_echo" {
  name = "Backup ${pangolin_resource.echo.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_echo_url" {
  description = "ECHO - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_echo.push_token}"
  sensitive   = true
}
