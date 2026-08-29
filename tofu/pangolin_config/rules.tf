# NOTE: `data.pangolin_resources` (stackopshq/pangolin v1.6.1) silently returns
# only the first page of the API response (pageSize 20) and exposes no way to
# ask for more, which left resources beyond the 20th with no firewall rules at
# all and made the `for_each` keys unstable between plans.
# Reported upstream against stackopshq/pangolin. Until it is fixed we query the
# API directly through the `http` provider so we can set `pageSize` and assert
# completeness against `pagination.total`.
data "http" "pangolin_resources" {
  url = "${local.pangolin_url}/v1/org/${local.pangolin_org_id}/resources?pageSize=1000"

  request_headers = {
    Authorization = "Bearer ${local.pangolin_api_key}"
    Accept        = "application/json"
  }
}

locals {
  pangolin_resources_raw = jsondecode(data.http.pangolin_resources.response_body).data

  # Field names are normalised back to the provider's snake_case naming so the
  # `for_each` keys below stay byte-identical to the ones already in state.
  pangolin_resources = [
    for resource in local.pangolin_resources_raw.resources : {
      id          = resource.resourceId
      name        = resource.name
      nice_id     = try(resource.niceId, null)
      full_domain = try(resource.fullDomain, null)
      domain_id   = try(resource.domainId, null)
    }
  ]
}

# A `check` block would only emit a warning; a precondition actually stops the
# apply, which is what we want if the list is ever truncated again.
resource "terraform_data" "pangolin_resources_complete" {
  input = length(local.pangolin_resources)

  lifecycle {
    precondition {
      condition     = length(local.pangolin_resources) == local.pangolin_resources_raw.pagination.total
      error_message = "Pangolin resource list is truncated: got ${length(local.pangolin_resources)} of ${local.pangolin_resources_raw.pagination.total} resources. Firewall rules would be applied to only part of the fleet."
    }
  }
}

locals {
  # Monitoring is located in Germany
  allowed_countries = ["FR", "DE"]

  resource_country_pairs = {
    for pair in setproduct(local.pangolin_resources, local.allowed_countries) :
    "${pair[0].name}-${pair[1]}" => {
      resource_id = pair[0].id
      country     = pair[1]
      priority    = index(local.allowed_countries, pair[1]) + 1
    }
  }
}

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
  for_each    = { for resource in local.pangolin_resources : tostring("${resource.id}-${resource.name}") => resource.id }
  resource_id = each.value
  action      = "DROP"
  match       = "COUNTRY"
  value       = "ALL"
  priority    = 99
}
