resource "pangolin_resource" "immich_swipe" {
  name      = "Immich Swipe"
  subdomain = "swipe-photos"
  domain_id = local.domain_ids["sylvain.cloud"]
  protocol  = "tcp"
  sso       = true
}

resource "pangolin_resource_role" "immich_swipe" {
  resource_id = pangolin_resource.immich_swipe.id
  role_id     = pangolin_role.apps["immich"].id
}

resource "pangolin_target" "immich_swipe" {
  resource_id = pangolin_resource.immich_swipe.id
  site_id     = pangolin_site.pi.id
  ip          = "immich-swipe"
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

resource "pangolin_resource_access_token" "immich_swipe" {
  resource_id = pangolin_resource.immich_swipe.id
  title       = "Healthcheck ${pangolin_resource.immich_swipe.name}"
}

output "immich_swipe_access_token" {
  description = "IMMICH_SWIPE - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.immich_swipe.id,
    token = pangolin_resource_access_token.immich_swipe.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "immich_swipe" {
  name            = "Healthcheck ${pangolin_resource.immich_swipe.name}"
  url             = "https://${pangolin_resource.immich_swipe.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.immich_swipe.id),
    "P-Access-Token"    = pangolin_resource_access_token.immich_swipe.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_immich_swipe" {
  name = "Backup ${pangolin_resource.immich_swipe.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_immich_swipe_url" {
  description = "IMMICH_SWIPE - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_immich_swipe.push_token}"
  sensitive   = true
}
