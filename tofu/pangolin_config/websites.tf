# ---------------------------------------------------------------------------
# Public apps: Pangolin resources, their targets and their monitoring.
#
# Every public app used to repeat the same hundred lines in its
# website_<app>.tf: the resource with its pins and its maintenance page, the
# SSO role binding, the target and its probe, the healthcheck access token, the
# inverted-keyword monitor, the backup push monitor and their outputs. That is
# written once here, for_each over local.websites, and each website_<app>.tf
# keeps only what is its own:
#
#   - `local.<app>_website`, its entry in local.websites (fields below);
#   - its path rules (`local.<app>_*_paths`, turned into rules by
#     local.path_bypasses in rules.tf), its other rules and extra tokens;
#   - its outputs: `uptime_backup_<app>_url`, read by Ansible, and
#     `<app>_access_token`. An output cannot be generated, hence one block each,
#     reading local.backup_push_urls / local.healthcheck_access_tokens below.
#
# The key is the former resource name (`meerkat_crm`, `demo_planning_kc`), and
# moved.tf maps every former address onto it: nothing was recreated. A
# recreated access token would have broken the monitor headers and the
# `*_access_token` outputs; a recreated push monitor, the push URL every backup
# job reads from this state.
#
# Entry fields - only name, subdomain and domain_id are required:
#
#   sso          default true. false only for Betisier, pinned by the
#                `every_public_resource_applies_its_rules` test.
#   enabled      default local.resource_pins.enabled. false also deactivates
#                the two monitors: a disabled resource has nothing to watch.
#   role         slug of pangolin_role.apps (roles.tf) bound to the resource.
#                Absent: no binding (Betisier and nextcloud have no SSO, NAS
#                and Proxmox are reached by the admin only).
#   healthcheck  default true: an access token and an inverted-keyword monitor.
#   backup       default false: a push monitor "Backup <name>".
#   target       the probed target: site_id, ip, port; optionally path and
#                priority (path routing, see website_flip_planning.tf), hc_path
#                (default "/") and hc_port (default port). Absent on NAS and
#                Proxmox, whose mirrored targets stay in their own file.
#   sub_targets  more targets on the same resource, keyed by a suffix: the
#                address is pangolin_target.website["<app>_<suffix>"].
# ---------------------------------------------------------------------------

locals {
  websites = {
    betisier         = local.betisier_website
    dawarich         = local.dawarich_website
    demo_planning    = local.demo_planning_website
    demo_planning_kc = local.demo_planning_kc_website
    echo             = local.echo_website
    flip_planning    = local.flip_planning_website
    gramps           = local.gramps_website
    immich           = local.immich_website
    immich_swipe     = local.immich_swipe_website
    karakeep         = local.karakeep_website
    meerkat_crm      = local.meerkat_crm_website
    monica           = local.monica_website
    nas              = local.nas_website
    nextcloud        = local.nextcloud_website
    paperless        = local.paperless_website
    proxmox          = local.proxmox_website
    rss              = local.rss_website
    scanopy          = local.scanopy_website
    searxng          = local.searxng_website
    trek             = local.trek_website
    wiki             = local.wiki_website
  }

  # `target` under the app's own key, each sub_target under "<app>_<suffix>":
  # the names the standalone pangolin_target resources had.
  website_targets = merge([
    for key, website in local.websites : merge(
      lookup(website, "target", null) == null ? {} : { (key) = merge(website.target, { website = key }) },
      { for suffix, target in lookup(website, "sub_targets", {}) : "${key}_${suffix}" => merge(target, { website = key }) },
    )
  ]...)

  # Entries that get an access token and an inverted-keyword monitor.
  healthchecked_websites = {
    for key, website in local.websites : key => website if lookup(website, "healthcheck", true)
  }

  # What the outputs of each website_<app>.tf read, in the format they always
  # had.
  healthcheck_access_tokens = {
    for key, token in pangolin_resource_access_token.healthcheck :
    key => jsonencode({ id = token.id, token = token.token })
  }

  backup_push_urls = {
    for key, monitor in uptimekuma_monitor_push.backup :
    key => "${local.uptimekuma_endpoint}/api/push/${monitor.push_token}"
  }
}

resource "pangolin_resource" "website" {
  for_each = local.websites

  name        = each.value.name
  subdomain   = each.value.subdomain
  domain_id   = each.value.domain_id
  protocol    = "tcp"
  sso         = lookup(each.value, "sso", true)
  apply_rules = true

  # Optional+computed: pinned so a plan can disagree with the API. See
  # resource_defaults.tf. `enabled` is the only one an entry may override.
  mode                    = local.resource_pins.mode
  ssl                     = local.resource_pins.ssl
  enabled                 = lookup(each.value, "enabled", local.resource_pins.enabled)
  block_access            = local.resource_pins.block_access
  email_whitelist_enabled = local.resource_pins.email_whitelist_enabled
  sticky_session          = local.resource_pins.sticky_session

  # Maintenance screen served automatically while no target is healthy.
  # See maintenance.tf.
  maintenance_mode_enabled = local.maintenance.enabled
  maintenance_mode_type    = local.maintenance.type
  maintenance_title        = local.maintenance.title
  maintenance_message      = local.maintenance.message

  # No resource declares a custom header. Flip Planning had an X-Pangolin one,
  # set by hand in the Pangolin UI for the application's MCP guard, which no
  # longer requires it, and the two demos were made in its image. Removing it
  # is a manual step in the UI, not an apply - the provider cannot round-trip
  # an emptied header list (the update response comes back as a string, not a
  # list) and fails with "cannot unmarshal string into ... headers of type
  # []ResourceHeader". Ignoring the attribute keeps Tofu from ever sending one.
  # It used to be ignored on those three resources only; a for_each cannot
  # vary its lifecycle, and since no apply can remove a header anyway, ignoring
  # it everywhere loses nothing Tofu could act on.
  lifecycle {
    ignore_changes = [headers]
  }
}

resource "pangolin_resource_role" "website" {
  for_each = { for key, website in local.websites : key => website if lookup(website, "role", null) != null }

  resource_id = pangolin_resource.website[each.key].id
  role_id     = pangolin_role.apps[each.value.role].id
}

# Health checks: `hc_scheme` / `hc_mode` / `hc_port` are optional+computed, and
# Pangolin stores them as NULL when Tofu does not send them - it does not fill
# in a default. A probe with no scheme never succeeds: gramps and scanopy, then
# the three Flip Planning targets sat at hcHealth="unhealthy" and Traefik
# dropped them from the load balancer ("no available server"). Declared
# explicitly so the probes can actually run. `hc_hostname` is not inferred from
# `ip` either: it is set to it, so the probe sends the right Host to the right
# container.
#
# Path routing: `path` set means a prefix match, and the catch-all "/" must
# carry the LOWEST priority number of its resource or it swallows the other
# prefixes (pinned by the `catch_all_target_has_lowest_priority` test).
resource "pangolin_target" "website" {
  for_each = local.website_targets

  resource_id     = pangolin_resource.website[each.value.website].id
  site_id         = each.value.site_id
  ip              = each.value.ip
  port            = each.value.port
  method          = "http"
  path            = lookup(each.value, "path", null)
  path_match_type = lookup(each.value, "path", null) == null ? null : "prefix"
  priority        = lookup(each.value, "priority", null)

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_port                = lookup(each.value, "hc_port", each.value.port)
  hc_hostname            = each.value.ip
  hc_path                = lookup(each.value, "hc_path", "/")
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

# The healthcheck's way past the SSO wall, sent by the monitor below as
# headers. Same blind spot on every SSO app: a revoked token shows Pangolin's
# login page, which holds no maintenance title either.
resource "pangolin_resource_access_token" "healthcheck" {
  for_each = local.healthchecked_websites

  resource_id = pangolin_resource.website[each.key].id
  title       = "Healthcheck ${pangolin_resource.website[each.key].name}"
}

resource "uptimekuma_monitor_http_keyword" "healthcheck" {
  for_each = local.healthchecked_websites

  name = "Healthcheck ${pangolin_resource.website[each.key].name}"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent          = uptimekuma_monitor_group.self_hosted.id
  url             = "https://${pangolin_resource.website[each.key].full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = pangolin_resource.website[each.key].enabled
  method          = "GET"

  # Inverted keyword on the maintenance title. See maintenance.tf.
  keyword        = local.maintenance.title
  invert_keyword = true
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.healthcheck[each.key].id),
    "P-Access-Token"    = pangolin_resource_access_token.healthcheck[each.key].token
  })
  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

# Every backup job pushes here (the URL is the `uptime_backup_<app>_url` output
# of the app's file, read by its playbook) after a successful run.
resource "uptimekuma_monitor_push" "backup" {
  for_each = { for key, website in local.websites : key => website if lookup(website, "backup", false) }

  name = "Backup ${pangolin_resource.website[each.key].name}"

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = pangolin_resource.website[each.key].enabled
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}
