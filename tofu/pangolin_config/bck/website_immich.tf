resource "pangolin_resource" "immich" {
  name      = "Immich"
  subdomain = "photos"
  domain_id = local.domain_ids["sylvain.cloud"]
  protocol  = "tcp"
  sso       = true
}

resource "pangolin_resource_role" "immich" {
  resource_id = pangolin_resource.immich.id
  role_id     = pangolin_role.apps["immich"].id
}

resource "pangolin_target" "immich" {
  resource_id = pangolin_resource.immich.id
  site_id     = pangolin_site.pi.id
  ip          = "immich"
  port        = 2283
  method      = "http"

  hc_enabled             = true
  hc_path                = "/"
  hc_method              = "GET"
  hc_status              = 200
  hc_headers             = []
  hc_headers             = []
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_pincode" "immich" {
  resource_id = pangolin_resource.immich.id
  pincode     = tostring(local.immich_pin)
}

resource "pangolin_resource_rule" "immich_home_ip" {
  resource_id = pangolin_resource.immich.id
  action      = "ACCEPT"
  match       = "IP"
  value       = local.home_ip
  priority    = 1
  enabled     = true
}

resource "pangolin_resource_access_token" "immich" {
  resource_id = pangolin_resource.immich.id
  title       = "Healthcheck ${pangolin_resource.immich.name}"
}

output "immich_access_token" {
  description = "IMMICH - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.immich.id,
    token = pangolin_resource_access_token.immich.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "immich" {
  name            = "Healthcheck ${pangolin_resource.immich.name}"
  url             = "https://${pangolin_resource.immich.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.immich.id),
    "P-Access-Token"    = pangolin_resource_access_token.immich.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_immich" {
  name = "Backup ${pangolin_resource.immich.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_immich_url" {
  description = "IMMICH - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_immich.push_token}"
  sensitive   = true
}
