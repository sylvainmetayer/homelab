resource "pangolin_resource" "betisier" {
  name      = "Betisier"
  subdomain = "betisier"
  domain_id = local.domain_ids["sylvain.dev"]
  protocol  = "tcp"
  sso       = false
  apply_rules = true
}

resource "pangolin_target" "betisier" {
  resource_id = pangolin_resource.betisier.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "betisier"
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

resource "pangolin_resource_access_token" "betisier" {
  resource_id = pangolin_resource.betisier.id
  title       = "Healthcheck ${pangolin_resource.betisier.name}"
}

output "betisier_access_token" {
  description = "BETISIER - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.betisier.id,
    token = pangolin_resource_access_token.betisier.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "betisier" {
  name            = "Healthcheck ${pangolin_resource.betisier.name}"
  url             = "https://${pangolin_resource.betisier.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.betisier.id),
    "P-Access-Token"    = pangolin_resource_access_token.betisier.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_betisier" {
  name = "Backup ${pangolin_resource.betisier.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_betisier_url" {
  description = "BETISIER - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_betisier.push_token}"
  sensitive   = true
}
