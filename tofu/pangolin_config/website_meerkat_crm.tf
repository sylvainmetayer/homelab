resource "pangolin_resource" "meerkat_crm" {
  name        = "Meerkat CRM"
  subdomain   = "crm"
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
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_port                = 8080
  hc_path                = "/"
  hc_method              = "GET"
  hc_status              = 200
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

resource "uptimekuma_monitor_http_keyword" "meerkat_crm" {
  name = "Healthcheck ${pangolin_resource.meerkat_crm.name}"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent          = uptimekuma_monitor_group.self_hosted.id
  url             = "https://${pangolin_resource.meerkat_crm.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  # Pangolin's automatic maintenance page is a Next.js server component proxied
  # by a Traefik router at priority 2000, so a service that is completely down
  # answers 200 with that page instead of failing. A plain status-code monitor
  # reads that as UP and never sends the downtime mail - the exact alerting the
  # maintenance page was added on top of.
  #
  # Inverted keyword: finding the maintenance title means DOWN. The title is
  # rendered server-side into the HTML (src/app/maintenance-screen/page.tsx), so
  # it is visible to a plain GET, and it is the same local the resources use, so
  # editing the page text cannot leave the monitors matching a stale string.
  keyword        = local.maintenance.title
  invert_keyword = true
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.meerkat_crm.id),
    "P-Access-Token"    = pangolin_resource_access_token.meerkat_crm.token
  })
  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

resource "uptimekuma_monitor_push" "backup_meerkat_crm" {
  name = "Backup ${pangolin_resource.meerkat_crm.name}"

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

output "uptime_backup_meerkat_crm_url" {
  description = "MEERKAT_CRM - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_meerkat_crm.push_token}"
  sensitive   = true
}
