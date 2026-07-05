resource "pangolin_resource" "paperless" {
  name        = "Paperless-ngx"
  subdomain   = "papiers"
  domain_id   = local.domain_ids["sylvain.cloud"]
  protocol    = "tcp"
  sso         = true
  apply_rules = true
}

resource "pangolin_resource_role" "paperless" {
  resource_id = pangolin_resource.paperless.id
  role_id     = pangolin_role.apps["paperless"].id
}

resource "pangolin_target" "paperless" {
  resource_id = pangolin_resource.paperless.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "paperless"
  port        = 8000
  method      = "http"

  hc_enabled             = true
  hc_hostname            = "paperless"
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

resource "pangolin_resource_access_token" "paperless" {
  resource_id = pangolin_resource.paperless.id
  title       = "Healthcheck ${pangolin_resource.paperless.name}"
}

output "paperless_access_token" {
  description = "PAPERLESS - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.paperless.id,
    token = pangolin_resource_access_token.paperless.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "paperless" {
  name            = "Healthcheck ${pangolin_resource.paperless.name}"
  url             = "https://${pangolin_resource.paperless.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.paperless.id),
    "P-Access-Token"    = pangolin_resource_access_token.paperless.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_paperless" {
  name = "Backup ${pangolin_resource.paperless.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_paperless_url" {
  description = "PAPERLESS - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_paperless.push_token}"
  sensitive   = true
}
