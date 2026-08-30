resource "pangolin_resource" "flip_planning" {
  name        = "Flip Planning"
  subdomain   = "flip-planning"
  domain_id   = local.domain_ids["sylvain.cloud"]
  protocol    = "tcp"
  mode        = "http"
  sso         = true
  apply_rules = true

  # These are optional+computed, so leaving them out made OpenTofu plan them
  # as "(known after apply)" on every update. Pinned to the values Pangolin
  # actually holds, read from GET /v1/resource/76.
  ssl                     = true
  enabled                 = true
  block_access            = false
  email_whitelist_enabled = false
  sticky_session          = false

  # Set by hand in the Pangolin UI and declared here so Tofu stops planning
  # its removal: the provider cannot round-trip an emptied header list (the
  # update response comes back as a string, not a list) and the apply fails
  # with "cannot unmarshal string into ... headers of type []ResourceHeader".
  headers = [
    {
      name  = "X-Pangolin"
      value = "true"
    },
  ]
}

resource "pangolin_resource_role" "flip_planning" {
  resource_id = pangolin_resource.flip_planning.id
  role_id     = pangolin_role.apps["flip-planning"].id
}

resource "pangolin_target" "flip_planning" {
  resource_id = pangolin_resource.flip_planning.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "flip-planning"
  port        = 8080
  method      = "http"

  # Catch-all target, must have a lower priority than the pgAdmin one.
  path            = "/"
  path_match_type = "prefix"
  priority        = 1

  # Health checks: `hc_scheme` / `hc_mode` / `hc_port` are optional+computed, and
  # Pangolin stores them as NULL when Tofu does not send them - it does not fill
  # in a default. A probe with no scheme never succeeds, so all three targets sat
  # at hcHealth="unhealthy" and Traefik dropped them from the load balancer
  # ("no available server"). Declared explicitly so the probes can actually run.
  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "flip-planning"
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

# pgAdmin is served on the /db sub-path of the same resource, so it is protected
# by the same SSO / role. pgAdmin is told about its root via SCRIPT_NAME=/db,
# hence no path rewrite here.
resource "pangolin_target" "flip_planning_pgadmin" {
  resource_id = pangolin_resource.flip_planning.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "flip-planning-pgadmin"
  port        = 80
  method      = "http"

  path            = "/db"
  path_match_type = "prefix"
  priority        = 2

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "flip-planning-pgadmin"
  hc_port                = 80
  hc_path                = "/db/misc/ping"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_target" "flip_planning_mailpit" {
  resource_id = pangolin_resource.flip_planning.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "flip-planning-mailpit"
  port        = 8025
  method      = "http"

  path            = "/mail"
  path_match_type = "prefix"
  priority        = 3

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_hostname            = "flip-planning-mailpit"
  hc_port                = 8025
  hc_path                = "/mail/livez"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_access_token" "flip_planning" {
  resource_id = pangolin_resource.flip_planning.id
  title       = "Healthcheck ${pangolin_resource.flip_planning.name}"
}

output "flip_planning_access_token" {
  description = "FLIP_PLANNING - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.flip_planning.id,
    token = pangolin_resource_access_token.flip_planning.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http" "flip_planning" {
  name            = "Healthcheck ${pangolin_resource.flip_planning.name}"
  url             = "https://${pangolin_resource.flip_planning.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.flip_planning.id),
    "P-Access-Token"    = pangolin_resource_access_token.flip_planning.token
  })
  expiry_notification = true
  tags                = [{ tag_id : uptimekuma_tag.self_hosted.id }]
}

resource "uptimekuma_monitor_push" "backup_flip_planning" {
  name = "Backup ${pangolin_resource.flip_planning.name}"

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [{ tag_id : uptimekuma_tag.backup.id }]
}

output "uptime_backup_flip_planning_url" {
  description = "FLIP_PLANNING - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_flip_planning.push_token}"
  sensitive   = true
}
