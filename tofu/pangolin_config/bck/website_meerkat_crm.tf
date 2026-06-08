resource "pangolin_resource" "meerkat_crm" {
  name      = "Meerkat CRM"
  subdomain = "crm"
  domain_id = local.domain_ids["sylvain.cloud"]
  protocol  = "tcp"
  sso       = true
}

resource "pangolin_resource_role" "meerkat_crm" {
  resource_id = pangolin_resource.meerkat_crm.id
  role_id     = pangolin_role.apps["meerkat-crm"].id
}

resource "pangolin_target" "meerkat_crm" {
  resource_id = pangolin_resource.meerkat_crm.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "meerkat-frontend"
  port        = 8080
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

resource "pangolin_resource_access_token" "meerkat_crm" {
  resource_id = pangolin_resource.meerkat_crm.id
  title       = "Healthcheck ${pangolin_resource.meerkat_crm.name}"
}

output "meerkat_crm_access_token" {
  description = "MEERKAT_CRM - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.meerkat_crm.id,
    token = pangolin_resource_access_token.meerkat_crm.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "meerkat_crm" {
  name            = "Healthcheck ${pangolin_resource.meerkat_crm.name}"
  url             = "https://${pangolin_resource.meerkat_crm.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.meerkat_crm.id),
    "P-Access-Token"    = pangolin_resource_access_token.meerkat_crm.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_meerkat_crm" {
  name = "Backup ${pangolin_resource.meerkat_crm.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_meerkat_crm_url" {
  description = "MEERKAT_CRM - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_meerkat_crm.push_token}"
  sensitive   = true
}
