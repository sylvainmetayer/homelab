# `pangolin_resources` data source silently truncates to the first 20 items (API pagination not handled)

## Summary

`data.pangolin_resources` returns only the **first page** of the Pangolin API
response (20 items by default) while reporting no error and exposing no way to
ask for more. Any config that drives `for_each` from this data source silently
operates on a truncated list.

This is not just "missing items". Because the API's page-1 window is not
guaranteed to be stable, the set of keys produced by `for_each` **changes
between plans**, so OpenTofu alternately destroys and recreates resources that
should be untouched. It also means resources beyond the 20th silently receive
none of the configuration the module is supposed to apply to every resource —
in our case, country-based firewall rules.

The `pangolin_resources` schema exposes a single computed attribute:

```
pangolin_resources:
    resources [computed]
```

There is no `limit`, `offset`, `page` or `page_size` argument, so this cannot
be worked around in HCL.

## Environment

| | |
|---|---|
| Provider | `stackopshq/pangolin` **v1.6.1** |
| OpenTofu | v1.12.6 (linux_amd64) |
| Pangolin API | self-hosted, `/v1/org/{orgId}/resources` |
| Org size | 23 resources |

## Minimal reproducible example

Requires an org with **more than 20 resources** (the API's default `pageSize`).

```hcl
terraform {
  required_providers {
    pangolin = {
      source  = "stackopshq/pangolin"
      version = "~> 1.6"
    }
  }
}

provider "pangolin" {
  url     = var.pangolin_url
  api_key = var.pangolin_api_key
  org_id  = var.pangolin_org_id
}

data "pangolin_resources" "all" {}

output "resource_count" {
  value = length(data.pangolin_resources.all.resources)
}

output "resource_names" {
  value = sort([for r in data.pangolin_resources.all.resources : r.name])
}
```

```console
$ tofu apply

resource_count = 20      # <-- the org has 23
```

### Cross-check against the API

The same org, queried directly, reports the true total and honours `pageSize`:

```console
# default: page 1 only, and the response says so
$ curl -s -H "Authorization: Bearer $PANGOLIN_API_KEY" \
    "https://pangolin.example.com/v1/org/$ORG/resources" \
  | jq '.data.pagination, (.data.resources | length)'
{
  "total": 23,
  "pageSize": 20,
  "page": 1
}
20

# the endpoint already supports pageSize -- it returns everything
$ curl -s -H "Authorization: Bearer $PANGOLIN_API_KEY" \
    "https://pangolin.example.com/v1/org/$ORG/resources?pageSize=1000" \
  | jq '.data.pagination, (.data.resources | length)'
{
  "total": 23,
  "pageSize": 1000,
  "page": 1
}
23
```

So the data needed to detect and fix the truncation (`pagination.total`) is
already present in the response the provider consumes, and the parameter needed
to fetch the rest (`pageSize`, or `page`) is already accepted by the API.

## Expected behaviour

`data.pangolin_resources.all.resources` contains **all 23** resources — either
because the provider paginates transparently until `pagination.total` is
reached, or because the practitioner can raise the page size explicitly.

## Actual behaviour

It contains 20, with no warning, no error, and no attribute exposing that the
list was cut short.

## Why this is worse than a missing-items bug

The documented pattern for this data source is to fan out over it:

```hcl
resource "pangolin_resource_rule" "block_country" {
  for_each = {
    for r in data.pangolin_resources.all.resources : "${r.id}-${r.name}" => r.id
  }
  resource_id = each.value
  action      = "DROP"
  match       = "COUNTRY"
  value       = "ALL"
  priority    = 99
}
```

With a truncated and unstable page-1 window, consecutive `tofu plan` runs on an
**unchanged** configuration produced different `for_each` maps:

```
# plan A
  # pangolin_resource_rule.block_country["33-Semaphore"] will be destroyed
  #   (because key ["33-Semaphore"] is not in for_each map)

# plan B, same config, minutes later
  # pangolin_resource_rule.block_country["81-Scanopy"] will be created
```

Two consequences:

1. **Rules churn.** Resources drop in and out of the map, so the provider
   destroys and recreates firewall rules that nobody asked to change.
2. **Silent security gap.** In our org the three resources that never appear on
   page 1 have had *no* country rules at all since the org grew past 20 — three
   publicly-exposed HTTP resources with the geo-filtering their config claims to
   give them simply absent. Nothing in the plan output indicates this.

Point 2 is the reason we'd class this as more than cosmetic: the failure mode is
a config that reports success while leaving part of the fleet unprotected.

## Scope — likely not limited to `pangolin_resources`

14 list-style data sources in v1.6.1 share the same shape (one computed
collection, no paging arguments):

```
pangolin_access_tokens, pangolin_api_keys, pangolin_blueprints,
pangolin_domain_dns_records, pangolin_domains, pangolin_idps, pangolin_orgs,
pangolin_resource_roles, pangolin_resource_targets, pangolin_resources,
pangolin_roles, pangolin_site_resources, pangolin_sites, pangolin_users
```

Spot-checking the corresponding endpoints on our instance, the same
`pageSize: 20` default applies to at least `sites`, `roles` and `users`:

```console
sites    -> {"total": 4,  "pageSize": 20, "page": 1}
roles    -> {"total": 20, "pageSize": 20, "page": 1}
users    -> {"total": 6,  "pageSize": 20, "page": 1}
domains  -> {"total": 2,  "limit": 1000, "offset": 0}     # different scheme
```

Note `roles` sits at exactly 20 — it will start truncating on the 21st role
created, with the same silence. `domains` appears to use `limit`/`offset`
rather than `page`/`pageSize`, so a fix probably needs to handle both
conventions rather than assuming one.

For contrast, the log data sources (`pangolin_access_logs`,
`pangolin_request_logs`, `pangolin_connection_logs`, …) *do* expose `limit`,
`offset` and a computed `total`, so the pattern already exists in this codebase.

## Suggested fix

In rough order of preference:

1. **Paginate transparently.** Have the list data sources loop until
   `len(accumulated) >= pagination.total`. This is the least surprising
   behaviour: a data source named `pangolin_resources` returning *some*
   resources is the trap.
2. **Failing that, expose `page_size` / `limit` + a computed `total`,** so
   practitioners can size the request and assert completeness themselves:

   ```hcl
   data "pangolin_resources" "all" {
     page_size = 1000
   }

   check "not_truncated" {
     assert {
       condition     = length(data.pangolin_resources.all.resources) == data.pangolin_resources.all.total
       error_message = "Pangolin resource list truncated."
     }
   }
   ```
3. **At minimum, make truncation loud** — surface `total` as a computed
   attribute and emit a provider warning diagnostic when the returned list is
   shorter than it. Silent truncation in a `for_each` source is the part that
   causes real damage.

## Current workaround

For anyone hitting this before a fix lands: bypass the data source with the
`http` provider, which lets you set `pageSize` and read `pagination.total`.
Renaming the fields back to the provider's naming keeps existing `for_each`
keys stable, so no rules are destroyed and recreated on the switch:

```hcl
data "http" "pangolin_resources" {
  url = "${var.pangolin_url}/v1/org/${var.pangolin_org_id}/resources?pageSize=1000"
  request_headers = {
    Authorization = "Bearer ${var.pangolin_api_key}"
    Accept        = "application/json"
  }
}

locals {
  _raw = jsondecode(data.http.pangolin_resources.response_body).data

  pangolin_resources = [
    for r in local._raw.resources : {
      id          = r.resourceId
      name        = r.name
      nice_id     = r.niceId
      full_domain = r.fullDomain
      domain_id   = r.domainId
    }
  ]
}

# NB: a `check` block would only emit a warning here. To actually stop the
# apply when the list is truncated, the assertion has to be a precondition.
resource "terraform_data" "pangolin_resources_complete" {
  lifecycle {
    precondition {
      condition     = length(local.pangolin_resources) == local._raw.pagination.total
      error_message = "Pangolin resources truncated: ${length(local.pangolin_resources)}/${local._raw.pagination.total}."
    }
  }
}
```

Caveat worth stating: this puts the raw response body — including every
resource's target IPs and ports — into state, which the provider data source
did not do to the same extent.
