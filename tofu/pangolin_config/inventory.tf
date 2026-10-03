# ---------------------------------------------------------------------------
# Target, access token and role inventory audits.
#
# Same blind spot as the one `terraform_data.rule_inventory` (rules.tf) closed
# for rules, on the three other object types the 31/08/2026 audit found drift
# in: a target on SSH PI, two access tokens made by hand ("MCP" on Flip
# Planning, "todo wip" on Immich) and three roles nobody declared (Admin,
# Member, Restreint). All of them were found by reading the API by hand - the
# plan compares what this configuration owns against itself and has no way to
# see anything else. See issue #525.
#
# Same shape for all three: read the live list, refuse to run on a list that is
# unreadable or truncated, then fail the plan on any live id this
# configuration did not create and that is not listed as a known exception.
# Each exception list also fails the plan when one of its entries no longer
# exists, so deleting a leftover in the UI forces its entry to be removed too.
#
# The ids are compared, not the names: the API is the only source for an id,
# while two objects can share a title (two "MCP" tokens is a token too many).
# ---------------------------------------------------------------------------

# --- Targets ----------------------------------------------------------------
#
# Reuses `data.http.pangolin_targets` (rules.tf), which covers every resource
# in `local.managed_resources`; unreadable responses are already reported by
# `terraform_data.target_probe_config`. Resources in `local.unmanaged_resources`
# (SSH PI) are deliberately not read: their target belongs to the same
# exception as the resource itself, see unmanaged_resource_monitors.tf.

locals {
  # HCL cannot enumerate the instances of a resource that has no `for_each`, so
  # a new pangolin_target has to be added here by hand. Forgetting it fails the
  # plan with the new target listed as undeclared - loud on purpose.
  declared_targets = [
    pangolin_target.bbox,
    pangolin_target.betisier,
    pangolin_target.dawarich,
    pangolin_target.demo_planning,
    pangolin_target.demo_planning_assets,
    pangolin_target.demo_planning_kc,
    pangolin_target.demo_planning_kc_assets,
    pangolin_target.demo_planning_kc_keycloak,
    pangolin_target.demo_planning_kc_mailpit,
    pangolin_target.demo_planning_kc_pgadmin,
    pangolin_target.demo_planning_mailpit,
    pangolin_target.demo_planning_pgadmin,
    pangolin_target.echo,
    pangolin_target.flip_planning,
    pangolin_target.flip_planning_assets,
    pangolin_target.flip_planning_mailpit,
    pangolin_target.flip_planning_pgadmin,
    pangolin_target.gramps,
    pangolin_target.immich,
    pangolin_target.immich_swipe,
    pangolin_target.meerkat_crm,
    pangolin_target.monica,
    pangolin_target.nas,
    pangolin_target.nextcloud,
    pangolin_target.paperless,
    pangolin_target.proxmox,
    pangolin_target.rss,
    pangolin_target.scanopy,
    pangolin_target.searxng,
    pangolin_target.traefik_dashboard,
    pangolin_target.trek,
    pangolin_target.wiki,
  ]

  declared_target_ids = toset([for target in local.declared_targets : tostring(target.id)])

  undeclared_targets = flatten([
    for name, response in data.http.pangolin_targets : [
      for target in try(jsondecode(response.response_body).data.targets, []) :
      "${name}#${target.targetId} (${coalesce(try(target.ip, null), "?")}:${coalesce(try(target.port, null), "?")}${try(target.path, null) == null ? "" : " ${target.path}"})"
      if !contains(local.declared_target_ids, tostring(target.targetId))
    ]
  ])
}

resource "terraform_data" "target_inventory" {
  input = length(local.declared_targets)

  lifecycle {
    precondition {
      condition = length(local.undeclared_targets) == 0
      error_message = join(" ", [
        "Targets live in Pangolin that this configuration did not create:",
        "${join(", ", local.undeclared_targets)}.",
        "Either declare them (a pangolin_target resource, plus an entry in",
        "local.declared_targets) or delete them in Pangolin.",
      ])
    }
  }
}

# --- Access tokens ----------------------------------------------------------

data "http" "pangolin_access_tokens" {
  # `limit` already defaults to 1000; set explicitly because the truncation
  # check below depends on it.
  url = "${local.pangolin_url}/v1/org/${local.pangolin_org_id}/access-tokens?limit=1000"

  request_headers = {
    Authorization = "Bearer ${local.pangolin_api_key}"
    Accept        = "application/json"
  }
}

locals {
  declared_access_tokens = [
    pangolin_resource_access_token.betisier,
    pangolin_resource_access_token.dawarich,
    pangolin_resource_access_token.demo_planning,
    pangolin_resource_access_token.echo,
    pangolin_resource_access_token.flip_planning,
    pangolin_resource_access_token.gramps,
    pangolin_resource_access_token.immich,
    pangolin_resource_access_token.immich_swipe,
    pangolin_resource_access_token.meerkat_crm,
    pangolin_resource_access_token.monica,
    pangolin_resource_access_token.nas,
    pangolin_resource_access_token.nextcloud,
    pangolin_resource_access_token.paperless,
    pangolin_resource_access_token.proxmox,
    pangolin_resource_access_token.rss,
    pangolin_resource_access_token.scanopy,
    pangolin_resource_access_token.searxng,
    pangolin_resource_access_token.ssh_pi,
    pangolin_resource_access_token.trek,
    pangolin_resource_access_token.wiki,
  ]

  # Tokens made by hand, keyed "<resource name> / <title>" since their ids are
  # not known to this configuration. Taking one over means recreating it - a
  # token's secret is only ever returned at creation - so whatever uses it has
  # to be reconfigured with the new value.
  unmanaged_access_tokens = {
    # Used by the MCP client of Flip Planning: recreating it from here would
    # break that client until it is given the new secret.
    "Flip Planning / MCP" = "MCP client"
    # Purpose unknown as of the 31/08/2026 audit. Delete it in Pangolin (and
    # this entry) once confirmed unused.
    "Immich / todo wip" = "unknown"
  }

  access_tokens_raw = try(jsondecode(data.http.pangolin_access_tokens.response_body).data, null)

  # Both fields can be null (untitled token, left join on the resource), and
  # `try` does not catch a null - `coalesce` does.
  live_access_tokens = [
    for token in try(local.access_tokens_raw.accessTokens, []) : {
      id    = tostring(token.accessTokenId)
      label = "${coalesce(try(token.resourceName, null), "?")} / ${coalesce(try(token.title, null), "(untitled)")}"
    }
  ]

  declared_access_token_ids = toset([for token in local.declared_access_tokens : tostring(token.id)])

  foreign_access_tokens = [
    for token in local.live_access_tokens : token
    if !contains(local.declared_access_token_ids, token.id)
  ]

  undeclared_access_tokens = [
    for token in local.foreign_access_tokens : "${token.label} (${token.id})"
    if !contains(keys(local.unmanaged_access_tokens), token.label)
  ]

  # An exception covers exactly one token: a second hand-made token with the
  # same resource and title is a new token, not the one that was reviewed.
  excused_access_tokens = [
    for token in local.foreign_access_tokens : token.label
    if contains(keys(local.unmanaged_access_tokens), token.label)
  ]

  dangling_access_token_exceptions = setsubtract(
    keys(local.unmanaged_access_tokens),
    local.excused_access_tokens
  )
}

resource "terraform_data" "access_token_inventory" {
  input = length(local.live_access_tokens)

  lifecycle {
    precondition {
      condition = local.access_tokens_raw != null && try(local.access_tokens_raw.accessTokens, null) != null
      error_message = join(" ", [
        "Could not read the access tokens (HTTP ${data.http.pangolin_access_tokens.status_code}).",
        "The API key needs the listAccessTokens action.",
        "The audit below cannot run, so the plan is stopped rather than passing on no data.",
      ])
    }

    # `pagination.total` on this endpoint counts the org's *resources*, not its
    # tokens (server/routers/accessToken/listAccessTokens.ts), so it cannot be
    # compared against. A full page is the only reliable sign of truncation.
    precondition {
      condition     = length(local.live_access_tokens) < try(local.access_tokens_raw.pagination.limit, 1000)
      error_message = "Pangolin returned a full page of access tokens (${length(local.live_access_tokens)}): the list may be truncated, so the audit below is meaningless."
    }

    precondition {
      condition = length(local.undeclared_access_tokens) == 0
      error_message = join(" ", [
        "Access tokens live in Pangolin that this configuration did not create:",
        "${join(", ", local.undeclared_access_tokens)}.",
        "Either declare them (a pangolin_resource_access_token resource, plus an",
        "entry in local.declared_access_tokens), delete them in Pangolin, or list",
        "them in local.unmanaged_access_tokens with the reason they stay manual.",
      ])
    }

    precondition {
      condition     = length(local.excused_access_tokens) == length(distinct(local.excused_access_tokens))
      error_message = "Several live access tokens match the same entry of local.unmanaged_access_tokens: ${join(", ", local.excused_access_tokens)}. Each exception covers one token; delete the extra ones."
    }

    precondition {
      condition     = length(local.dangling_access_token_exceptions) == 0
      error_message = "local.unmanaged_access_tokens lists tokens that no longer exist in Pangolin: ${join(", ", local.dangling_access_token_exceptions)}. Remove them."
    }
  }
}

# --- Roles ------------------------------------------------------------------
#
# `data.pangolin_roles` is not used: the provider calls this endpoint without
# `pageSize`, which defaults to 20, and the org already holds 19 roles.

data "http" "pangolin_roles" {
  url = "${local.pangolin_url}/v1/org/${local.pangolin_org_id}/roles?pageSize=1000"

  request_headers = {
    Authorization = "Bearer ${local.pangolin_api_key}"
    Accept        = "application/json"
  }
}

locals {
  # Roles this configuration does not own, by name, with the reason why.
  unmanaged_roles = {
    # Created with the organization; neither can be declared.
    "Admin"  = "built-in"
    "Member" = "built-in"
    # Created by hand. `pangolin_role` could take it over: declare it, then
    # `tofu import pangolin_role.<name> <roleId>` and drop this entry.
    "Restreint" = "manual"
  }

  roles_raw = try(jsondecode(data.http.pangolin_roles.response_body).data, null)

  live_roles = [
    for role in try(local.roles_raw.roles, []) : {
      id   = tostring(role.roleId)
      name = role.name
    }
  ]

  declared_role_ids = toset([for role in pangolin_role.apps : tostring(role.id)])

  undeclared_roles = [
    for role in local.live_roles : "${role.name} (${role.id})"
    if !contains(local.declared_role_ids, role.id) && !contains(keys(local.unmanaged_roles), role.name)
  ]

  dangling_role_exceptions = setsubtract(
    keys(local.unmanaged_roles),
    [for role in local.live_roles : role.name]
  )
}

resource "terraform_data" "role_inventory" {
  input = length(local.live_roles)

  lifecycle {
    precondition {
      condition = local.roles_raw != null && try(local.roles_raw.roles, null) != null
      error_message = join(" ", [
        "Could not read the roles (HTTP ${data.http.pangolin_roles.status_code}).",
        "The API key needs the listRoles action.",
        "The audit below cannot run, so the plan is stopped rather than passing on no data.",
      ])
    }

    precondition {
      condition     = length(local.live_roles) == try(local.roles_raw.pagination.total, -1)
      error_message = "Pangolin role list is truncated: got ${length(local.live_roles)} of ${try(local.roles_raw.pagination.total, "?")}. The audit below would be meaningless."
    }

    precondition {
      condition = length(local.undeclared_roles) == 0
      error_message = join(" ", [
        "Roles live in Pangolin that this configuration did not create:",
        "${join(", ", local.undeclared_roles)}.",
        "Either declare them (add the slug to local.apps in roles.tf, or a",
        "pangolin_role imported with `tofu import`), delete them in Pangolin, or",
        "list them in local.unmanaged_roles with the reason they stay manual.",
      ])
    }

    precondition {
      condition     = length(local.dangling_role_exceptions) == 0
      error_message = "local.unmanaged_roles lists roles that no longer exist in Pangolin: ${join(", ", local.dangling_role_exceptions)}. Remove them."
    }
  }
}
