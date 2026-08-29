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
    "00NTF - spliit"            = 12 # disabled in Pangolin
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
