# Appli pilote du stockage sur le NAS (fichiers + Postgres sur l'export NFS,
# sauvegardés par borg). Voir nas-storage-docker/homelab-storage-architecture.md.
resource "pangolin_resource" "nginx_demo" {
  name        = "Nginx Demo"
  subdomain   = "nginx"
  domain_id   = local.domain_ids["sylvain.cloud"]
  protocol    = "tcp"
  sso         = true
  apply_rules = true

  # Optional+computed: pinned so a plan can disagree with the API. See
  # resource_defaults.tf.
  ssl                     = local.resource_pins.ssl
  enabled                 = local.resource_pins.enabled
  block_access            = local.resource_pins.block_access
  email_whitelist_enabled = local.resource_pins.email_whitelist_enabled
  sticky_session          = local.resource_pins.sticky_session

  # Maintenance screen served automatically while no target is healthy.
  # See maintenance.tf.
  maintenance_mode_enabled = local.maintenance.enabled
  maintenance_mode_type    = local.maintenance.type
  maintenance_title        = local.maintenance.title
  maintenance_message      = local.maintenance.message
}

resource "pangolin_resource_role" "nginx_demo" {
  resource_id = pangolin_resource.nginx_demo.id
  role_id     = pangolin_role.apps["nginx-demo"].id
}

resource "pangolin_target" "nginx_demo" {
  resource_id = pangolin_resource.nginx_demo.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "nginx-demo"
  port        = 80
  method      = "http"

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_port                = 80
  hc_hostname            = "nginx-demo"
  hc_path                = "/"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_access_token" "nginx_demo" {
  resource_id = pangolin_resource.nginx_demo.id
  title       = "Healthcheck ${pangolin_resource.nginx_demo.name}"
}

output "nginx_demo_access_token" {
  description = "NGINX_DEMO - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.nginx_demo.id,
    token = pangolin_resource_access_token.nginx_demo.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http_keyword" "nginx_demo" {
  name = "Healthcheck ${pangolin_resource.nginx_demo.name}"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent          = uptimekuma_monitor_group.self_hosted.id
  url             = "https://${pangolin_resource.nginx_demo.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  # Inverted keyword: the maintenance page answers 200. See website_gramps.tf.
  keyword        = local.maintenance.title
  invert_keyword = true
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.nginx_demo.id),
    "P-Access-Token"    = pangolin_resource_access_token.nginx_demo.token
  })
  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

resource "uptimekuma_monitor_push" "backup_nginx_demo" {
  name = "Backup ${pangolin_resource.nginx_demo.name}"

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

output "uptime_backup_nginx_demo_url" {
  description = "NGINX_DEMO - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_nginx_demo.push_token}"
  sensitive   = true
}
