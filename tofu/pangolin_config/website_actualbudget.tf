resource "pangolin_resource" "actualbudget" {
  name        = "ActualBudget"
  subdomain   = "budget"
  domain_id   = local.domain_ids["sylvain.cloud"]
  protocol    = "tcp"
  sso         = true
  apply_rules = true
}

resource "pangolin_resource_role" "actualbudget" {
  resource_id = pangolin_resource.actualbudget.id
  role_id     = pangolin_role.apps["actualbudget"].id
}

resource "pangolin_target" "actualbudget" {
  resource_id = pangolin_resource.actualbudget.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "actualbudget"
  port        = 5006
  method      = "http"

  hc_enabled             = true
  hc_hostname            = "actualbudget"
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

resource "pangolin_resource_access_token" "actualbudget" {
  resource_id = pangolin_resource.actualbudget.id
  title       = "Healthcheck ${pangolin_resource.actualbudget.name}"
}

output "actualbudget_access_token" {
  description = "ACTUALBUDGET - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.actualbudget.id,
    token = pangolin_resource_access_token.actualbudget.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "actualbudget" {
  name            = "Healthcheck ${pangolin_resource.actualbudget.name}"
  url             = "https://${pangolin_resource.actualbudget.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.actualbudget.id),
    "P-Access-Token"    = pangolin_resource_access_token.actualbudget.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_actualbudget" {
  name = "Backup ${pangolin_resource.actualbudget.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_actualbudget_url" {
  description = "ACTUALBUDGET - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_actualbudget.push_token}"
  sensitive   = true
}
