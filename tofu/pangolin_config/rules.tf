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

  # Apps managed by this configuration. The key is the resource's Pangolin
  # `name` and MUST be a literal: `for_each` keys have to be known at plan
  # time, while the id on the right may still be unknown for a resource that
  # does not exist yet. That asymmetry is what buys single-apply convergence.
  #
  # Adding an app here is not optional - the coverage precondition below fails
  # the plan if a live resource has no entry.
  managed_resources = {
    "Betisier"         = pangolin_resource.betisier.id
    "Dawarich"         = pangolin_resource.dawarich.id
    "Echo"             = pangolin_resource.echo.id
    "Flip Planning"    = pangolin_resource.flip_planning.id
    "Gramps"           = pangolin_resource.gramps.id
    "Immich"           = pangolin_resource.immich.id
    "Immich Swipe"     = pangolin_resource.immich_swipe.id
    "Meerkat CRM"      = pangolin_resource.meerkat_crm.id
    "Monica CRM"       = pangolin_resource.monica.id
    "Paperless-ngx"    = pangolin_resource.paperless.id
    "RSS"              = pangolin_resource.rss.id
    "Scanopy"          = pangolin_resource.scanopy.id
    "SearXNG"          = pangolin_resource.searxng.id
    "TREK"             = pangolin_resource.trek.id
    "Wiki (Bookstack)" = pangolin_resource.wiki.id
    "nextcloud"        = pangolin_resource.nextcloud.id
  }

  # Resources created by hand in the Pangolin UI, outside this configuration.
  # Short, static list; the ids are pinned deliberately so the rules no longer
  # depend on a live lookup. The `enabled = false` ones are kept so this change
  # destroys no existing rule - prune them once they are confirmed dead.
  unmanaged_resources = {
    "00NTF - Proxmox"           = 4  # enabled
    "SSH PI"                    = 38 # enabled
    "00NTF - NAS"               = 75 # enabled
    "00NTF - Dashboard Traefik" = 2  # disabled in Pangolin
    "00NTF - BBOX"              = 15 # disabled in Pangolin
  }

  rule_targets = merge(local.managed_resources, local.unmanaged_resources)

  resource_country_pairs = {
    for pair in setproduct(keys(local.rule_targets), local.allowed_countries) :
    "${pair[0]}-${pair[1]}" => {
      resource_id = local.rule_targets[pair[0]]
      country     = pair[1]
      priority    = index(local.allowed_countries, pair[1]) + 1
    }
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

  # Enabled in Pangolin but with no entry above: publicly reachable with no
  # geo-filtering at all. This is the failure that went unnoticed for months.
  uncovered_resources = setsubtract(local.pangolin_live_enabled, keys(local.rule_targets))

  # Pinned ids that no longer exist: an unmanaged resource was deleted or
  # renamed in the UI and the pin is now dangling.
  dangling_pins = setsubtract(
    keys(local.unmanaged_resources),
    [for resource in local.pangolin_live_raw.resources : resource.name]
  )
}

# A `check` block would only emit a warning and let the apply proceed, which is
# exactly the silence we are trying to remove. Preconditions hard-fail.
resource "terraform_data" "geo_rule_coverage" {
  input = length(local.rule_targets)

  lifecycle {
    precondition {
      condition     = length(local.pangolin_live_raw.resources) == local.pangolin_live_raw.pagination.total
      error_message = "Pangolin resource list is truncated: got ${length(local.pangolin_live_raw.resources)} of ${local.pangolin_live_raw.pagination.total}. The coverage check below would be meaningless."
    }

    precondition {
      condition     = length(local.uncovered_resources) == 0
      error_message = "Enabled Pangolin resources with no country rules: ${join(", ", local.uncovered_resources)}. Add them to local.managed_resources (if this config creates them) or local.unmanaged_resources (if they were made by hand)."
    }

    precondition {
      condition     = length(local.dangling_pins) == 0
      error_message = "local.unmanaged_resources pins resources that no longer exist in Pangolin: ${join(", ", local.dangling_pins)}. Remove them."
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
  for_each = local.rule_targets

  resource_id = each.value
  action      = "DROP"
  match       = "COUNTRY"
  value       = "ALL"
  priority    = 99
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

  unhealthy_targets = [
    for target in local.live_targets : target.label
    if target.hc_enabled && target.hc_health != "healthy"
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
