resource "pangolin_resource" "scanopy" {
  name        = "Scanopy"
  subdomain   = "scan"
  domain_id   = local.domain_ids["sylvain.cloud"]
  protocol    = "tcp"
  sso         = true
  apply_rules = true
}

resource "pangolin_resource_role" "scanopy" {
  resource_id = pangolin_resource.scanopy.id
  role_id     = pangolin_role.apps["scanopy"].id
}

resource "pangolin_target" "scanopy" {
  resource_id = pangolin_resource.scanopy.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "scanopy-server"
  port        = 60072
  method      = "http"

  hc_enabled             = true
  hc_hostname            = "scanopy-server"
  hc_path                = "/"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_access_token" "scanopy" {
  resource_id = pangolin_resource.scanopy.id
  title       = "Healthcheck ${pangolin_resource.scanopy.name}"
}

output "scanopy_access_token" {
  description = "SCANOPY - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.scanopy.id,
    token = pangolin_resource_access_token.scanopy.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "scanopy" {
  name            = "Healthcheck ${pangolin_resource.scanopy.name}"
  url             = "https://${pangolin_resource.scanopy.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.scanopy.id),
    "P-Access-Token"    = pangolin_resource_access_token.scanopy.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_scanopy" {
  name = "Backup ${pangolin_resource.scanopy.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_scanopy_url" {
  description = "SCANOPY - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_scanopy.push_token}"
  sensitive   = true
}
