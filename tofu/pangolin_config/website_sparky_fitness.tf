resource "pangolin_resource" "sparky_fitness" {
  name        = "Sparky Fitness"
  subdomain   = "sante"
  domain_id   = local.domain_ids["sylvain.cloud"]
  protocol    = "tcp"
  sso         = true
  apply_rules = true
}

resource "pangolin_resource_role" "sparky_fitness" {
  resource_id = pangolin_resource.sparky_fitness.id
  role_id     = pangolin_role.apps["sparky-fitness"].id
}

resource "pangolin_target" "sparky_fitness" {
  resource_id = pangolin_resource.sparky_fitness.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "sparkyfitness-frontend"
  port        = 80
  method      = "http"

  hc_enabled             = true
  hc_hostname                = "sparkyfitness-frontend"
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

resource "pangolin_resource_access_token" "sparky_fitness" {
  resource_id = pangolin_resource.sparky_fitness.id
  title       = "Healthcheck ${pangolin_resource.sparky_fitness.name}"
}

output "sparky_fitness_access_token" {
  description = "SPARKY_FITNESS - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.sparky_fitness.id,
    token = pangolin_resource_access_token.sparky_fitness.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "sparky_fitness" {
  name            = "Healthcheck ${pangolin_resource.sparky_fitness.name}"
  url             = "https://${pangolin_resource.sparky_fitness.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.sparky_fitness.id),
    "P-Access-Token"    = pangolin_resource_access_token.sparky_fitness.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_sparky_fitness" {
  name = "Backup ${pangolin_resource.sparky_fitness.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_sparky_fitness_url" {
  description = "SPARKY_FITNESS - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_sparky_fitness.push_token}"
  sensitive   = true
}
