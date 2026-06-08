resource "pangolin_resource" "rss" {
  name      = "RSS"
  subdomain = "rss"
  domain_id = local.domain_ids["sylvain.cloud"]
  protocol  = "tcp"
  sso       = true
  apply_rules = true
}

resource "pangolin_resource_role" "rss" {
  resource_id = pangolin_resource.rss.id
  role_id     = pangolin_role.apps["rss"].id
}

resource "pangolin_target" "rss" {
  resource_id = pangolin_resource.rss.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "rss"
  port        = 80
  method      = "http"

  hc_enabled             = true
  hc_path                = "/"
  hc_method              = "GET"
  hc_headers             = []
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_access_token" "rss" {
  resource_id = pangolin_resource.rss.id
  title       = "Healthcheck ${pangolin_resource.rss.name}"
}

output "rss_access_token" {
  description = "RSS - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.rss.id,
    token = pangolin_resource_access_token.rss.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "rss" {
  name            = "Healthcheck ${pangolin_resource.rss.name}"
  url             = "https://${pangolin_resource.rss.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.rss.id),
    "P-Access-Token"    = pangolin_resource_access_token.rss.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_rss" {
  name = "Backup ${pangolin_resource.rss.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_rss_url" {
  description = "RSS - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_rss.push_token}"
  sensitive   = true
}
