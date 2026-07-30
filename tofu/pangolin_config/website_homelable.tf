resource "pangolin_resource" "homelable" {
  name        = "Homelable"
  subdomain   = "homelab"
  domain_id   = local.domain_ids["sylvain.cloud"]
  protocol    = "tcp"
  sso         = true
  apply_rules = true
}

resource "pangolin_resource_role" "homelable" {
  resource_id = pangolin_resource.homelable.id
  role_id     = pangolin_role.apps["homelable"].id
}

resource "pangolin_target" "homelable" {
  resource_id = pangolin_resource.homelable.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "homelable-frontend"
  port        = 80
  method      = "http"

  hc_enabled             = true
  hc_hostname            = "homelable-frontend"
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

resource "pangolin_resource_access_token" "homelable" {
  resource_id = pangolin_resource.homelable.id
  title       = "Healthcheck ${pangolin_resource.homelable.name}"
}

output "homelable_access_token" {
  description = "HOMELABLE - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.homelable.id,
    token = pangolin_resource_access_token.homelable.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "homelable" {
  name            = "Healthcheck ${pangolin_resource.homelable.name}"
  url             = "https://${pangolin_resource.homelable.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.homelable.id),
    "P-Access-Token"    = pangolin_resource_access_token.homelable.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_homelable" {
  name = "Backup ${pangolin_resource.homelable.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_homelable_url" {
  description = "HOMELABLE - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_homelable.push_token}"
  sensitive   = true
}
