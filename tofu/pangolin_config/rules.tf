# ---------------------------------------------------------------------------
# Country firewall rules.
#
# The rule set is derived from THIS CONFIGURATION, not from a read of the live
# Pangolin infrastructure. The previous design drove both `for_each` loops from
# `data.pangolin_resources`, which caused three problems at once:
#
#   1. Truncation. That data source returns only the first API page (pageSize
#      20, no limit/offset argument) so resources beyond the 20th silently got
#      no rules at all.
#   2. Churn. The page-1 window is not stable, so consecutive plans on
#      unchanged config alternately destroyed and recreated rules.
#   3. Two-apply convergence. A brand new app only appeared in the live list on
#      the *second* apply, so it spent one apply publicly exposed with no
#      geo-filtering.
#
# Deriving the keys from config fixes all three: the keys are literal strings,
# known at plan time, so a new app gets its rules in the same apply that
# creates it. The live list is still read below, but only as an AUDIT: it can
# fail the plan, it can no longer decide what gets built.
# ---------------------------------------------------------------------------

locals {
  # Monitoring is located in Germany
  allowed_countries = ["FR", "DE"]

  # Rules are evaluated in ascending priority order and the first one that
  # matches decides, so the numbering is a layout rather than a label. The
  # country rules only PASS - "carry on to the authentication methods" - so
  # anything sitting behind them is never reached by a request coming from FR
  # or DE. A bypass that has to hold whatever the caller's country therefore
  # needs a slot in front of them, and the provider rejects a priority below 1,
  # so the country band starts at 10 and leaves that room:
  #
  #    1       DROP of any path holding a backslash, on every resource that has
  #            a path rule below (pangolin_resource_rule.backslash_guard). Alone
  #            in its slot, so it is always evaluated before them.
  #    2 -  9  app-specific rules evaluated before the geo-filter:
  #            - path ACCEPTs, every one of them from local.path_bypasses
  #              (pangolin_resource_rule.path_bypass);
  #            - trek_mcp, a PASS, the only standalone path rule: skips the
  #              country rules but keeps the authentication;
  #            - the home-IP ACCEPTs at 9 (immich_home_ip, dawarich_home_ip,
  #              trek_home_ip). Behind the country PASS they were never reached
  #              from the home connection, which is French.
  #            Rules sharing a priority on one resource all carry the same
  #            action, so the order Pangolin picks between them cannot matter
  #            (pinned by the `tied_rules_share_their_action` test).
  #   10 - 11  PASS COUNTRY FR, PASS COUNTRY DE
  #   20       PASS COUNTRY <trip>, while var.travel_countries keeps it open
  #   99       DROP COUNTRY ALL
  country_rule_priority_base = 10

  # Trip countries get their own slot rather than following FR and DE, so that
  # FR and DE keep theirs whatever comes and goes here. One fixed priority for
  # all of them: PASS rules on disjoint countries can be evaluated in any
  # order, so numbering them would only renumber every other trip country - an
  # in-place update of all its rules - each time one comes or goes. Pangolin
  # does not require distinct priorities.
  travel_country_priority = 20

  # Each entry of var.travel_countries gets exactly one status, on the plan's
  # clock: `permanent` (already in allowed_countries, opens nothing more),
  # `active`, or `expired`.
  travel_country_status = {
    for country, until in var.travel_countries : country => (
      contains(local.allowed_countries, country) ? "permanent" :
      timecmp(plantimestamp(), until) < 0 ? "active" : "expired"
    )
  }

  active_travel_countries = sort([
    for country, status in local.travel_country_status : country if status == "active"
  ])

  # Entries that open nothing: dead weight in variables.tf.
  stale_travel_countries = sort([
    for country, status in local.travel_country_status : "${country} (${status})" if status != "active"
  ])

  # Apps managed by this configuration. The key is the resource's Pangolin
  # `name` and MUST be a literal: `for_each` keys have to be known at plan
  # time, while the id on the right may still be unknown for a resource that
  # does not exist yet. That asymmetry is what buys single-apply convergence.
  #
  # Every one of them gets the country rules. Adding an app here is not
  # optional - the coverage precondition below fails the plan if a live,
  # enabled resource has no entry. There used to be a second map,
  # `unmanaged_resources`, pinning by id the resources made by hand in the
  # Pangolin UI; its last entry, `SSH PI`, duplicated the private
  # `pi.internal` site resource and was deleted, so the map and its audit went
  # with it.
  managed_resources = {
    "Betisier"         = pangolin_resource.betisier.id
    "Dawarich"         = pangolin_resource.dawarich.id
    "Demo Planning"    = pangolin_resource.demo_planning.id
    "Demo Planning KC" = pangolin_resource.demo_planning_kc.id
    "Echo"             = pangolin_resource.echo.id
    "Flip Planning"    = pangolin_resource.flip_planning.id
    "Gramps"           = pangolin_resource.gramps.id
    "Immich"           = pangolin_resource.immich.id
    "Immich Swipe"     = pangolin_resource.immich_swipe.id
    "Karakeep"         = pangolin_resource.karakeep.id
    "Meerkat CRM"      = pangolin_resource.meerkat_crm.id
    "Monica CRM"       = pangolin_resource.monica.id
    "NAS"              = pangolin_resource.nas.id
    "nextcloud"        = pangolin_resource.nextcloud.id
    "Paperless-ngx"    = pangolin_resource.paperless.id
    "Proxmox"          = pangolin_resource.proxmox.id
    "RSS"              = pangolin_resource.rss.id
    "Scanopy"          = pangolin_resource.scanopy.id
    "SearXNG"          = pangolin_resource.searxng.id
    "TREK"             = pangolin_resource.trek.id
    "Wiki (Bookstack)" = pangolin_resource.wiki.id
  }


  # Trip countries share the resource and the key format of the permanent ones
  # ("<resource>-<country>"): opening and closing GB only ever adds or
  # destroys the "-GB" instances, never touches FR or DE.
  resource_country_pairs = merge(
    {
      for pair in setproduct(keys(local.managed_resources), local.allowed_countries) :
      "${pair[0]}-${pair[1]}" => {
        resource_id = local.managed_resources[pair[0]]
        country     = pair[1]
        priority    = index(local.allowed_countries, pair[1]) + local.country_rule_priority_base
      }
    },
    {
      for pair in setproduct(keys(local.managed_resources), local.active_travel_countries) :
      "${pair[0]}-${pair[1]}" => {
        resource_id = local.managed_resources[pair[0]]
        country     = pair[1]
        priority    = local.travel_country_priority
      }
    },
  )
}

# Only a reminder: a stale entry already opens nothing (see
# local.travel_country_status), it is just dead weight in variables.tf.
check "travel_countries_stale" {
  assert {
    condition     = length(local.stale_travel_countries) == 0
    error_message = "Entrées de var.travel_countries (variables.tf) qui n'ouvrent rien, à retirer : ${join(", ", local.stale_travel_countries)}. Un pays expiré est refermé par ce plan ; un pays permanent est déjà ouvert par local.allowed_countries."
  }
}

# ---------------------------------------------------------------------------
# Audit only. Never feed this into a `for_each`.
#
# `data.pangolin_resources` is not used because it silently truncates to the
# first API page; we call the endpoint directly so we can set `pageSize` and
# check the result against `pagination.total`.
# ---------------------------------------------------------------------------
data "http" "pangolin_resources" {
  url = "${local.pangolin_url}/v1/org/${local.pangolin_org_id}/resources?pageSize=1000"

  request_headers = {
    Authorization = "Bearer ${local.pangolin_api_key}"
    Accept        = "application/json"
  }
}

locals {
  pangolin_live_raw = jsondecode(data.http.pangolin_resources.response_body).data

  pangolin_live_enabled = [
    for resource in local.pangolin_live_raw.resources :
    resource.name if try(resource.enabled, false)
  ]

  pangolin_live_disabled = [
    for resource in local.pangolin_live_raw.resources :
    resource.name if !try(resource.enabled, false)
  ]

  # Enabled in Pangolin but with no entry above: publicly reachable with no
  # geo-filtering at all. This is the failure that went unnoticed for months.
  uncovered_resources = setsubtract(local.pangolin_live_enabled, keys(local.managed_resources))
}

# A `check` block would only emit a warning and let the apply proceed, which is
# exactly the silence we are trying to remove. Preconditions hard-fail.
resource "terraform_data" "geo_rule_coverage" {
  input = length(local.managed_resources)

  lifecycle {
    precondition {
      condition     = length(local.pangolin_live_raw.resources) == local.pangolin_live_raw.pagination.total
      error_message = "Pangolin resource list is truncated: got ${length(local.pangolin_live_raw.resources)} of ${local.pangolin_live_raw.pagination.total}. The coverage check below would be meaningless."
    }

    precondition {
      condition     = length(local.uncovered_resources) == 0
      error_message = "Enabled Pangolin resources with no country rules: ${join(", ", local.uncovered_resources)}. Declare them in a website_*.tf and add them to local.managed_resources, or delete (or disable) them in Pangolin."
    }
  }
}

# ---------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------

resource "pangolin_resource_rule" "allow_countries" {
  for_each = local.resource_country_pairs

  resource_id = each.value.resource_id
  action      = "PASS"
  match       = "COUNTRY"
  value       = each.value.country
  priority    = each.value.priority
  enabled     = true
}

# Block all other countries (catch-all rule with low priority)
resource "pangolin_resource_rule" "block_country" {
  for_each = local.managed_resources

  resource_id = each.value
  action      = "DROP"
  match       = "COUNTRY"
  value       = "ALL"
  priority    = 99
}

# ---------------------------------------------------------------------------
# Path bypasses.
#
# What a public link, a client app or a hosted assistant needs to reach without
# the SSO wall and from any country: its page, its API calls, its static files,
# an MCP server, an OAuth or OIDC surface. Each app documents its own list next
# to its resource (website_<app>.tf, `local.<app>_*_paths`, a map path =>
# priority in the 2 - 9 band); this block only turns them into rules. Every one
# of them is an ACCEPT: the app's own secret (share token, signed URL, API
# password, MCP key, Keycloak login...) is what protects the content behind it,
# and the app-side check is named next to each path. The only path rule that is
# not an ACCEPT, TREK's `/mcp` PASS, stays a standalone resource
# (website_trek.tf).
#
# The key is the resource's Pangolin name, as in local.managed_resources.
# ---------------------------------------------------------------------------
locals {
  path_bypasses = {
    "Dawarich"         = local.dawarich_share_paths
    "Demo Planning"    = local.demo_planning_mcp_paths
    "Demo Planning KC" = local.demo_planning_kc_keycloak_paths
    "Flip Planning"    = local.flip_planning_mcp_paths
    "Karakeep"         = local.karakeep_public_paths
    "Meerkat CRM"      = local.meerkat_crm_dav_paths
    "Monica CRM"       = local.monica_dav_paths
    "nextcloud"        = merge(local.nextcloud_client_paths, local.nextcloud_share_paths)
    "Paperless-ngx"    = local.paperless_share_paths
    "RSS"              = local.rss_api_paths
    "TREK"             = merge(local.trek_mcp_public_paths, local.trek_share_paths)
  }

  path_bypass_rules = merge([
    for name, paths in local.path_bypasses : {
      for path, priority in paths : "${name} ${path}" => {
        resource_id = local.managed_resources[name]
        path        = path
        priority    = priority
      }
    }
  ]...)

  # Resources with a path rule that lives in a standalone resource rather than
  # in local.path_bypasses: only TREK's `/mcp` PASS (pangolin_resource_rule.
  # trek_mcp, website_trek.tf), the one path rule that is not an ACCEPT. Listed
  # by hand for the same reason as local.declared_extra_rules below, so that
  # the guard stays even if TREK's ACCEPTs go away.
  standalone_path_rule_resources = [
    "TREK",
  ]

  # Pangolin resolves `..`, `%2e%2e` and `%2F` before matching a path
  # (server/lib/pathMatch.ts) but leaves a backslash alone, while the WHATWG URL
  # parser on a Node backend turns it into `/`: `/shared/..\..\api/trips`
  # matches an ACCEPT on `/shared/*` and is then served as `/api/trips`. Some
  # backends here are not Node, but none has a legitimate URL holding a
  # backslash, so every resource with a path rule gets the DROP rather than
  # an audit per backend.
  backslash_guarded_resources = toset(concat(keys(local.path_bypasses), local.standalone_path_rule_resources))
}

resource "pangolin_resource_rule" "path_bypass" {
  for_each = local.path_bypass_rules

  resource_id = each.value.resource_id
  action      = "ACCEPT"
  match       = "PATH"
  value       = each.value.path
  priority    = each.value.priority
  enabled     = true
}

# `%5C` is the backslash: the pattern is percent-decoded before matching, and
# an encoded backslash in a request is decoded the same way. The leading and
# trailing `*` take zero or more segments, the middle one is a single segment
# holding a backslash anywhere; Pangolin escapes regex metacharacters before
# turning `*` into `.*`, so the `\` stays a literal backslash.
resource "pangolin_resource_rule" "backslash_guard" {
  for_each = local.backslash_guarded_resources

  resource_id = local.managed_resources[each.key]
  action      = "DROP"
  match       = "PATH"
  value       = "/*/*%5C*/*"
  priority    = 1
  enabled     = true
}

# ---------------------------------------------------------------------------
# Probe configuration audit.
#
# `hc_scheme` / `hc_mode` / `hc_port` are optional+computed on pangolin_target.
# Left undeclared they mean "accept whatever the API decides", and Pangolin does
# not reliably fill a default: it stored NULL for gramps and scanopy while
# filling `http` for trek and dawarich, all four created by the same apply. A
# probe with no scheme can never build a URL, so it always fails, the target is
# marked unhealthy, Traefik drops it from the load balancer and the site serves
# "no available server" - with `tofu plan` reporting "No changes" throughout,
# because an undeclared computed attribute accepts any value the API holds.
#
# Every target now declares those three fields, so a plan compares them against
# a literal and would surface the drift. This is the second net: it reads the
# live probes and fails the plan outright.
#
# There is no org-wide targets endpoint, hence one request per managed resource.
# ---------------------------------------------------------------------------
data "http" "pangolin_targets" {
  for_each = local.managed_resources

  # No pagination argument here: unlike the resources endpoint this one
  # rejects `pageSize` outright, and already defaults to a limit of 1000.
  url = "${local.pangolin_url}/v1/resource/${each.value}/targets"

  request_headers = {
    Authorization = "Bearer ${local.pangolin_api_key}"
    Accept        = "application/json"
  }
}

locals {
  # An audit that silently sees nothing is worse than no audit, so a response
  # that does not decode into a target list is collected and reported below
  # rather than being flattened away into an empty result.
  failed_target_lookups = [
    for name, response in data.http.pangolin_targets :
    "${name} (HTTP ${response.status_code})"
    if try(jsondecode(response.response_body).data.targets, null) == null
  ]

  live_targets = flatten([
    for name, response in data.http.pangolin_targets : [
      for target in try(jsondecode(response.response_body).data.targets, []) : {
        resource   = name
        label      = "${name}#${target.targetId}${try(target.path, null) == null ? "" : " ${target.path}"}"
        hc_enabled = try(target.hcEnabled, false)
        hc_scheme  = try(target.hcScheme, null)
        hc_port    = try(target.hcPort, null)
        hc_health  = try(target.hcHealth, "unknown")
      }
    ]
  ])

  # An enabled probe with no scheme or no port can only ever fail. This is the
  # exact state gramps and scanopy sat in while both sites served 503.
  unusable_probes = [
    for target in local.live_targets : target.label
    if target.hc_enabled && (target.hc_scheme == null || target.hc_port == null)
  ]

  # A disabled resource (Gramps, stopped on purpose) keeps its target and its
  # probe for the day it comes back; its probe failing meanwhile is expected,
  # and a permanent warning would only teach to skim past real ones.
  unhealthy_targets = [
    for target in local.live_targets : target.label
    if target.hc_enabled && target.hc_health != "healthy"
    && !contains(local.pangolin_live_disabled, target.resource)
  ]
}

resource "terraform_data" "target_probe_config" {
  input = length(local.live_targets)

  lifecycle {
    precondition {
      condition = length(local.failed_target_lookups) == 0
      error_message = join(" ", [
        "Could not read the targets of:",
        "${join(", ", local.failed_target_lookups)}.",
        "The audit below cannot run, so the plan is stopped rather than passing on no data.",
      ])
    }

    precondition {
      condition = length(local.unusable_probes) == 0
      error_message = join(" ", [
        "Health check enabled but no scheme and/or no port, so the probe can never",
        "succeed and Pangolin will drop the target from the load balancer:",
        "${join(", ", local.unusable_probes)}.",
        "Declare hc_scheme / hc_mode / hc_port on the matching pangolin_target and apply.",
      ])
    }
  }
}

# Deliberately a `check`, not a precondition: unlike the probe *configuration*
# above, health is a runtime property. It is legitimately "unknown" for the few
# seconds after a target is created, and legitimately "unhealthy" whenever an
# app is genuinely down - neither should block an unrelated apply. Paging is
# Uptime Kuma's job; this only makes the state visible while you are in here.
check "target_health" {
  assert {
    condition     = length(local.unhealthy_targets) == 0
    error_message = "Targets whose probe is currently failing: ${join(", ", local.unhealthy_targets)}."
  }
}

# ---------------------------------------------------------------------------
# Rule inventory audit.
#
# `terraform_data.geo_rule_coverage` above asks "does every enabled resource
# have rules?" and stops there. It never asks "and nothing else?", which leaves
# anything added by hand in the Pangolin UI completely invisible: 00NTF -
# Proxmox carried ten leftover duplicate country rules while `tofu plan`
# reported "No changes" throughout, and the ACCEPT rule that opens the Flip
# Planning MCP server lived only in Pangolin until it was found by reading the
# API by hand. Both are the same blind spot - the plan only ever compared what
# this configuration owns against itself.
#
# The comparison is on rule *ids*, not on (action, match, value, priority): two
# rules can be semantically identical and still be two distinct rules, which is
# exactly the shape the Proxmox duplicates had. Every rule Pangolin holds must
# be one this configuration created.
#
# One request per resource; there is no org-wide rules endpoint.
# ---------------------------------------------------------------------------
data "http" "pangolin_rules" {
  for_each = local.managed_resources

  # This endpoint already defaults to a limit of 1000, and the truncation
  # precondition below refuses to trust a response that says otherwise.
  url = "${local.pangolin_url}/v1/resource/${each.value}/rules"

  request_headers = {
    Authorization = "Bearer ${local.pangolin_api_key}"
    Accept        = "application/json"
  }
}

locals {
  # App-specific rules, listed one by one. HCL cannot enumerate the instances of
  # a resource that has no `for_each`, so a new standalone pangolin_resource_rule
  # has to be added here by hand or the audit reports it as undeclared. That the
  # omission fails loudly is the point: the alternative is the silence above.
  declared_extra_rules = concat(
    [
      pangolin_resource_rule.dawarich_home_ip,
      pangolin_resource_rule.immich_home_ip,
      pangolin_resource_rule.trek_home_ip,
      pangolin_resource_rule.trek_mcp,
    ],
    values(pangolin_resource_rule.backslash_guard),
    values(pangolin_resource_rule.path_bypass),
  )

  # Stringified so the ids compare cleanly against the JSON numbers below.
  declared_rule_ids = toset(concat(
    [for rule in pangolin_resource_rule.allow_countries : tostring(rule.id)],
    [for rule in pangolin_resource_rule.block_country : tostring(rule.id)],
    [for rule in local.declared_extra_rules : tostring(rule.id)],
  ))

  # Same reasoning as failed_target_lookups: an audit that silently sees nothing
  # is worse than no audit, so an undecodable response is reported, not skipped.
  failed_rule_lookups = [
    for name, response in data.http.pangolin_rules :
    "${name} (HTTP ${response.status_code})"
    if try(jsondecode(response.response_body).data.rules, null) == null
  ]

  truncated_rule_lists = [
    for name, response in data.http.pangolin_rules : name
    if try(
      length(jsondecode(response.response_body).data.rules) != jsondecode(response.response_body).data.pagination.total,
      false
    )
  ]

  live_rules = flatten([
    for name, response in data.http.pangolin_rules : [
      for rule in try(jsondecode(response.response_body).data.rules, []) : {
        id    = tostring(rule.ruleId)
        label = "${name}#${rule.ruleId} (${rule.action} ${rule.match} ${rule.value}, priority ${rule.priority})"
      }
    ]
  ])

  # Live in Pangolin, created by something other than this configuration.
  undeclared_rules = [
    for rule in local.live_rules : rule.label
    if !contains(local.declared_rule_ids, rule.id)
  ]
}

resource "terraform_data" "rule_inventory" {
  input = length(local.live_rules)

  lifecycle {
    precondition {
      condition = length(local.failed_rule_lookups) == 0
      error_message = join(" ", [
        "Could not read the rules of:",
        "${join(", ", local.failed_rule_lookups)}.",
        "The audit below cannot run, so the plan is stopped rather than passing on no data.",
      ])
    }

    precondition {
      condition = length(local.truncated_rule_lists) == 0
      error_message = join(" ", [
        "Pangolin returned a truncated rule list for:",
        "${join(", ", local.truncated_rule_lists)}.",
        "The audit below would not see the missing rules, so it is meaningless.",
      ])
    }

    precondition {
      condition = length(local.undeclared_rules) == 0
      error_message = join(" ", [
        "Rules live in Pangolin that this configuration did not create:",
        "${join(", ", local.undeclared_rules)}.",
        "Either declare them (a pangolin_resource_rule resource, plus an entry in",
        "local.declared_extra_rules unless it comes from the loops above) or delete",
        "them in Pangolin. Note that the provider cannot import a rule: its",
        "ImportState trusts the `resourceId` of the API payload, which Pangolin",
        "returns as null, so the import writes resource_id = 0 and the follow-up",
        "read 404s. Delete the live rule and let an apply recreate it from config.",
      ])
    }
  }
}
