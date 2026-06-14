resource "pangolin_resource" "wiki" {
  name      = "Wiki (Bookstack)"
  subdomain = "wiki"
  domain_id = local.domain_ids["sylvain.cloud"]
  protocol  = "tcp"
  sso       = true
  apply_rules = true
}

resource "pangolin_resource_role" "wiki" {
  resource_id = pangolin_resource.wiki.id
  role_id     = pangolin_role.apps["wiki"].id
}

resource "pangolin_target" "wiki" {
  resource_id = pangolin_resource.wiki.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "bookstack"
  port        = 80
  method      = "http"

  hc_enabled             = true
  hc_path                = "/login"
  hc_method              = "GET"
  hc_status              = 200
  hc_headers             = []
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_access_token" "wiki" {
  resource_id = pangolin_resource.wiki.id
  title       = "Healthcheck ${pangolin_resource.wiki.name}"
}

output "wiki_access_token" {
  description = "WIKI - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.wiki.id,
    token = pangolin_resource_access_token.wiki.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "wiki" {
  name            = "Healthcheck ${pangolin_resource.wiki.name}"
  url             = "https://${pangolin_resource.wiki.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.wiki.id),
    "P-Access-Token"    = pangolin_resource_access_token.wiki.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_wiki" {
  name = "Backup ${pangolin_resource.wiki.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_wiki_url" {
  description = "WIKI - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_wiki.push_token}"
  sensitive   = true
}
