resource "pangolin_resource" "semaphore" {
  name      = "Semaphore"
  subdomain = "console"
  domain_id = local.domain_ids["sylvain.cloud"]
  protocol  = "tcp"
  sso       = true
  apply_rules = true
}

resource "pangolin_resource_role" "semaphore" {
  resource_id = pangolin_resource.semaphore.id
  role_id     = pangolin_role.apps["semaphore"].id
}

resource "pangolin_target" "semaphore" {
  resource_id = pangolin_resource.semaphore.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "semaphore"
  port        = 3000
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

resource "pangolin_resource_access_token" "semaphore" {
  resource_id = pangolin_resource.semaphore.id
  title       = "Healthcheck ${pangolin_resource.semaphore.name}"
}

output "semaphore_access_token" {
  description = "SEMAPHORE - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.semaphore.id,
    token = pangolin_resource_access_token.semaphore.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "semaphore" {
  name            = "Healthcheck ${pangolin_resource.semaphore.name}"
  url             = "https://${pangolin_resource.semaphore.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.semaphore.id),
    "P-Access-Token"    = pangolin_resource_access_token.semaphore.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_semaphore" {
  name = "Backup ${pangolin_resource.semaphore.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_semaphore_url" {
  description = "SEMAPHORE - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_semaphore.push_token}"
  sensitive   = true
}
