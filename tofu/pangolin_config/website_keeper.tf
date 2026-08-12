resource "pangolin_resource" "keeper" {
  name        = "Keeper"
  subdomain   = "cal-sync"
  domain_id   = local.domain_ids["sylvain.cloud"]
  protocol    = "tcp"
  sso         = true
  apply_rules = true
}

resource "pangolin_resource_role" "keeper" {
  resource_id = pangolin_resource.keeper.id
  role_id     = pangolin_role.apps["keeper"].id
}

resource "pangolin_target" "keeper" {
  resource_id = pangolin_resource.keeper.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "keeper-app"
  port        = 3000
  method      = "http"

  hc_enabled             = true
  hc_hostname            = "keeper-app"
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

resource "pangolin_resource_access_token" "keeper" {
  resource_id = pangolin_resource.keeper.id
  title       = "Healthcheck ${pangolin_resource.keeper.name}"
}

output "keeper_access_token" {
  description = "KEEPER - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.keeper.id,
    token = pangolin_resource_access_token.keeper.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "keeper" {
  name            = "Healthcheck ${pangolin_resource.keeper.name}"
  url             = "https://${pangolin_resource.keeper.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.keeper.id),
    "P-Access-Token"    = pangolin_resource_access_token.keeper.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_keeper" {
  name = "Backup ${pangolin_resource.keeper.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_keeper_url" {
  description = "KEEPER - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_keeper.push_token}"
  sensitive   = true
}
