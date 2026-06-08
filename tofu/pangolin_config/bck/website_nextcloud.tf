resource "pangolin_resource" "nextcloud" {
  name      = "nextcloud"
  subdomain = null
  domain_id = local.domain_ids["sylvain.cloud"]
  protocol  = "tcp"
  sso       = false
}

resource "pangolin_target" "nextcloud" {
  resource_id = pangolin_resource.nextcloud.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "nextcloud"
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

resource "pangolin_resource_access_token" "nextcloud" {
  resource_id = pangolin_resource.nextcloud.id
  title       = "Healthcheck ${pangolin_resource.nextcloud.name}"
}

output "nextcloud_access_token" {
  description = "NEXTCLOUD - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.nextcloud.id,
    token = pangolin_resource_access_token.nextcloud.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "nextcloud" {
  name            = "Healthcheck ${pangolin_resource.nextcloud.name}"
  url             = "https://${pangolin_resource.nextcloud.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.nextcloud.id),
    "P-Access-Token"    = pangolin_resource_access_token.nextcloud.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_nextcloud" {
  name = "Backup ${pangolin_resource.nextcloud.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_nextcloud_url" {
  description = "NEXTCLOUD - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_nextcloud.push_token}"
  sensitive   = true
}
