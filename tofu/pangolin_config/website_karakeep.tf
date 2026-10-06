resource "pangolin_resource" "karakeep" {
  name        = "Karakeep"
  subdomain   = "keep"
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

resource "pangolin_resource_role" "karakeep" {
  resource_id = pangolin_resource.karakeep.id
  role_id     = pangolin_role.apps["karakeep"].id
}

# The mobile app, the browser extension and the MCP server cannot go through the
# Pangolin SSO wall. Rather than letting `/api/*` bypass it, each one sends a
# Pangolin access token in its custom headers (P-Access-Token-Id /
# P-Access-Token) on top of its Karakeep API key: the API stays behind both
# the SSO wall and the geo-filter, and the mobile app's tRPC calls
# (/api/trpc), which the former `/api/v1/*` bypass never covered, get through
# too. The only paths left open are the public lists' below, none of which
# serves a private bookmark.
#
# One token per client, so a lost phone is revoked without touching the others.
# Read them with `tofu output -json karakeep_client_access_tokens`.
resource "pangolin_resource_access_token" "karakeep_clients" {
  for_each = toset(["mobile", "extension", "mcp"])

  resource_id = pangolin_resource.karakeep.id
  title       = "${pangolin_resource.karakeep.name} ${each.key}"
}

output "karakeep_client_access_tokens" {
  description = "KARAKEEP - En-têtes Pangolin des clients (app mobile, extension, MCP)"
  value = {
    for client, token in pangolin_resource_access_token.karakeep_clients : client => {
      "P-Access-Token-Id" = tostring(token.id)
      "P-Access-Token"    = token.token
    }
  }
  sensitive = true
}

# Public lists (list > Share > "Public list") are read by people with no
# account, wherever they are: these ACCEPTs sit in the 1 - 9 band of rules.tf,
# in front of the country rules, and skip the SSO wall. Each path is one the
# page /public/lists/<listId> actually requests, read off the Karakeep v0.33.2
# sources (apps/web/app/public, components/public/lists, packages/api); the
# `karakeep_public_paths_follow_the_image` test fails when the image moves, so
# that they are read again. Karakeep's own authorisation still applies behind
# every one of them, so a list that is not public answers 404.
#
# Deliberately not opened: /api/auth/session (next-auth refetches it when the
# tab regains focus; failing just logs a console error), /icons/* and
# /apple-icon.png (the tab's favicon only), and anything broader under /api.
locals {
  karakeep_public_paths = {
    # The server-rendered page itself (first 20 bookmarks included). The only
    # route under /public.
    "/public/lists/*" = 2

    # Next.js build output: JS chunks, CSS, the self-hosted Inter font and the
    # logo. Same bytes for every Karakeep install.
    "/_next/static/*" = 3

    # Banner images, screenshots and attached files. Served only with a token
    # the server signs per asset when it renders the list, with an expiry.
    "/api/public/*" = 4

    # Infinite scroll past the first page, the only tRPC query the page sends.
    # Spelled out in full, no wildcard: tRPC batches calls as a comma-joined
    # list in this one segment, so `publicBookmarks.*` also matched
    # `publicBookmarks.x,apiKeys.exchange` - a password-to-API-key exchange
    # open to the whole world, without SSO or geo-filter. An exact segment
    # matches a batch of this procedure alone and nothing else.
    "/api/trpc/publicBookmarks.getPublicBookmarksInList" = 5

    # The page's RSS button. Answers for a public list, or for a private one
    # only with its rssToken in the query string.
    "/api/v1/rss/lists/*" = 6
  }
}

resource "pangolin_resource_rule" "karakeep_public" {
  for_each = local.karakeep_public_paths

  resource_id = pangolin_resource.karakeep.id
  action      = "ACCEPT"
  match       = "PATH"
  value       = each.key
  priority    = each.value
  enabled     = true
}

# Evaluated before the ACCEPTs above: any path with a backslash in it is
# refused. Pangolin resolves `..`, `%2e%2e` and `%2F` before matching
# (server/lib/pathMatch.ts), but a backslash is just a character to it, so
# `/public/lists/..\..\api/v1/bookmarks` matches `/public/lists/*`, while
# the WHATWG URL parser on the Node side turns `\` into `/` and resolves the
# same path to `/api/v1/bookmarks`. No legitimate Karakeep URL carries one.
# `%5C` is the backslash: the pattern is decoded before matching, and an
# encoded `\` in a request is decoded the same way. The leading and trailing
# `*` take zero or more segments, the middle one is a single segment holding a
# backslash anywhere.
resource "pangolin_resource_rule" "karakeep_backslash" {
  resource_id = pangolin_resource.karakeep.id
  action      = "DROP"
  match       = "PATH"
  value       = "/*/*%5C*/*"
  priority    = 1
  enabled     = true
}

resource "pangolin_target" "karakeep" {
  resource_id = pangolin_resource.karakeep.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "karakeep"
  port        = 3000
  method      = "http"

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_port                = 3000
  hc_hostname            = "karakeep"
  hc_path                = "/api/health"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_access_token" "karakeep" {
  resource_id = pangolin_resource.karakeep.id
  title       = "Healthcheck ${pangolin_resource.karakeep.name}"
}

output "karakeep_access_token" {
  description = "KARAKEEP - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.karakeep.id,
    token = pangolin_resource_access_token.karakeep.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http_keyword" "karakeep" {
  name = "Healthcheck ${pangolin_resource.karakeep.name}"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent          = uptimekuma_monitor_group.self_hosted.id
  url             = "https://${pangolin_resource.karakeep.full_domain}"
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
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.karakeep.id),
    "P-Access-Token"    = pangolin_resource_access_token.karakeep.token
  })
  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

resource "uptimekuma_monitor_push" "backup_karakeep" {
  name = "Backup ${pangolin_resource.karakeep.name}"

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

output "uptime_backup_karakeep_url" {
  description = "KARAKEEP - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_karakeep.push_token}"
  sensitive   = true
}
