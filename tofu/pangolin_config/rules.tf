data "pangolin_resources" "all" {}

locals {
  # Monitoring is located in Germany
  allowed_countries = ["FR", "DE"]

  resource_country_pairs = {
    for pair in setproduct(data.pangolin_resources.all.resources, local.allowed_countries) :
    "${pair[0].id}-${pair[1]}" => {
      resource_id = pair[0].id
      country     = pair[1]
      priority    = index(local.allowed_countries, pair[1]) + 1
    }
  }
}

resource "pangolin_resource_rule" "allow_countries" {
  for_each = local.resource_country_pairs

  resource_id = each.value.resource_id
  action      = "ACCEPT"
  match       = "COUNTRY"
  value       = each.value.country
  priority    = each.value.priority
  enabled     = true
}

# Block all other countries (catch-all rule with low priority)
resource "pangolin_resource_rule" "block_country" {
  for_each    = { for resource in data.pangolin_resources.all.resources : tostring(resource.id) => resource.id }
  resource_id = each.value
  action      = "DROP"
  match       = "COUNTRY"
  value       = "ALL"
  priority    = 99
}
