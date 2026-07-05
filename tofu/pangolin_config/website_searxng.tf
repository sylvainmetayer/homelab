resource "pangolin_resource" "searxng" {
  name        = "SearXNG"
  subdomain   = "search"
  domain_id   = local.domain_ids["sylvain.cloud"]
  protocol    = "tcp"
  sso         = true
  apply_rules = true
}

resource "pangolin_resource_role" "searxng" {
  resource_id = pangolin_resource.searxng.id
  role_id     = pangolin_role.apps["searxng"].id
}

resource "pangolin_target" "searxng" {
  resource_id = pangolin_resource.searxng.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "searxng"
  port        = 8080
  method      = "http"

  hc_enabled             = true
  hc_hostname            = "searxng"
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

resource "pangolin_resource_access_token" "searxng" {
  resource_id = pangolin_resource.searxng.id
  title       = "Healthcheck ${pangolin_resource.searxng.name}"
}

output "searxng_access_token" {
  description = "SEARXNG - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.searxng.id,
    token = pangolin_resource_access_token.searxng.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "searxng" {
  name            = "Healthcheck ${pangolin_resource.searxng.name}"
  url             = "https://${pangolin_resource.searxng.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.searxng.id),
    "P-Access-Token"    = pangolin_resource_access_token.searxng.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_searxng" {
  name = "Backup ${pangolin_resource.searxng.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_searxng_url" {
  description = "SEARXNG - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_searxng.push_token}"
  sensitive   = true
}
