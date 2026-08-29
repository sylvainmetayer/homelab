resource "pangolin_resource" "gramps" {
  name        = "Gramps"
  subdomain   = "trees"
  domain_id   = local.domain_ids["sylvain.cloud"]
  protocol    = "tcp"
  sso         = true
  apply_rules = true
}

resource "pangolin_resource_role" "gramps" {
  resource_id = pangolin_resource.gramps.id
  role_id     = pangolin_role.apps["gramps"].id
}

resource "pangolin_target" "gramps" {
  resource_id = pangolin_resource.gramps.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "grampsweb"
  port        = 5000
  method      = "http"

  hc_enabled             = true
  hc_hostname            = "grampsweb"
  hc_path                = "/"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_access_token" "gramps" {
  resource_id = pangolin_resource.gramps.id
  title       = "Healthcheck ${pangolin_resource.gramps.name}"
}

output "gramps_access_token" {
  description = "GRAMPS - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.gramps.id,
    token = pangolin_resource_access_token.gramps.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "gramps" {
  name            = "Healthcheck ${pangolin_resource.gramps.name}"
  url             = "https://${pangolin_resource.gramps.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.gramps.id),
    "P-Access-Token"    = pangolin_resource_access_token.gramps.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_gramps" {
  name = "Backup ${pangolin_resource.gramps.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_gramps_url" {
  description = "GRAMPS - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_gramps.push_token}"
  sensitive   = true
}
