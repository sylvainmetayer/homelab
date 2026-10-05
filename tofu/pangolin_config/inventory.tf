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
# `check` blocks, not preconditions. The live lists are read at plan time,
# before anything is applied, so in two legitimate cases they disagree with the
# configuration for the length of one run:
#
#   - removing an app: its token and role are still live but no longer
#     declared;
#   - replacing a target or a token: the plan-time list still holds the old
#     id, and the new one only exists after the apply.
#
# A precondition turns both into a failed plan, or worse a failed apply after
# the change has been made. A check only warns, and the warning is gone on the
# next plan. The price is that real drift warns instead of blocking - it still
# shows on every plan until it is dealt with.
#
# (A check with a scoped data source would be re-read after the apply and
# avoid even the transient warning, but OpenTofu then prints every response
# body in full on every plan: hundreds of lines, token hashes included.)
#
# The ids are compared, not the names: two objects can share a title (two "MCP"
# tokens is a token too many). Every exception must match exactly one live
# object, so a stale or duplicated exception warns too.
# ---------------------------------------------------------------------------

# --- Targets ----------------------------------------------------------------
#
# The resource list `data.http.pangolin_resources` (rules.tf) already carries
# every resource's targets, and its truncation is already a precondition of
# `terraform_data.geo_rule_coverage`. Resources in `local.unmanaged_resources`
# (SSH PI) are deliberately left out: their target belongs to the same
# exception as the resource itself, see unmanaged_resource_monitors.tf.

locals {
  # HCL cannot enumerate the instances of a resource that has no `for_each`, so
  # a new pangolin_target has to be added here by hand. Forgetting it is
  # reported as an undeclared target - on purpose.
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

  audited_resource_ids = toset([for id in values(local.managed_resources) : tostring(id)])

  undeclared_targets = flatten([
    for resource in local.pangolin_live_raw.resources : [
      for target in try(resource.targets, []) :
      "${resource.name}#${target.targetId} (${coalesce(try(target.ip, null), "?")}:${coalesce(try(target.port, null), "?")})"
      if !contains(local.declared_target_ids, tostring(target.targetId))
    ] if contains(local.audited_resource_ids, tostring(resource.resourceId))
  ])
}

check "target_inventory" {
  assert {
    condition = length(local.undeclared_targets) == 0
    error_message = join(" ", [
      "Targets live in Pangolin that this configuration did not create:",
      "${join(", ", local.undeclared_targets)}.",
      "Either declare them (a pangolin_target resource, plus an entry in",
      "local.declared_targets) or delete them in Pangolin. Expected once while",
      "a target is being replaced.",
    ])
  }
}

# --- Access tokens ----------------------------------------------------------

data "http" "pangolin_access_tokens" {
  # `limit` already defaults to 1000; set explicitly because the truncation
  # assertion below depends on it.
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

  declared_access_token_ids = toset([for token in local.declared_access_tokens : tostring(token.id)])

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

  # Both label fields can be null (untitled token, left join on the resource),
  # and `try` does not catch a null - `coalesce` does.
  foreign_access_tokens = [
    for token in try(local.access_tokens_raw.accessTokens, []) : {
      id    = tostring(token.accessTokenId)
      label = "${coalesce(try(token.resourceName, null), "?")} / ${coalesce(try(token.title, null), "(untitled)")}"
    }
    if !contains(local.declared_access_token_ids, tostring(token.accessTokenId))
  ]

  undeclared_access_tokens = [
    for token in local.foreign_access_tokens : "${token.label} (${token.id})"
    if !contains(keys(local.unmanaged_access_tokens), token.label)
  ]

  # An exception covers exactly one token: no match means it is stale, a
  # second match is a new hand-made token, not the one that was reviewed.
  misused_access_token_exceptions = [
    for label in keys(local.unmanaged_access_tokens) : label
    if length([for token in local.foreign_access_tokens : token if token.label == label]) != 1
  ]
}

check "access_token_inventory" {
  # `pagination.total` on this endpoint counts the org's *resources*, not its
  # tokens (server/routers/accessToken/listAccessTokens.ts), so it cannot be
  # compared against. A full page is the only reliable sign of truncation.
  assert {
    condition = (
      try(local.access_tokens_raw.accessTokens, null) != null
      && length(try(local.access_tokens_raw.accessTokens, [])) < 1000
    )
    error_message = "Could not read the full access token list (HTTP ${data.http.pangolin_access_tokens.status_code}; the API key needs the listAccessTokens action): the token audit did not run."
  }

  assert {
    condition = length(local.undeclared_access_tokens) == 0
    error_message = join(" ", [
      "Access tokens live in Pangolin that this configuration did not create:",
      "${join(", ", local.undeclared_access_tokens)}.",
      "Either declare them (a pangolin_resource_access_token resource, plus an",
      "entry in local.declared_access_tokens), delete them in Pangolin, or list",
      "them in local.unmanaged_access_tokens with the reason they stay manual.",
      "Expected once while an app is removed or a token replaced.",
    ])
  }

  assert {
    condition     = length(local.misused_access_token_exceptions) == 0
    error_message = "These entries of local.unmanaged_access_tokens do not match exactly one live token: ${join(", ", local.misused_access_token_exceptions)}. Remove an entry whose token is gone; delete the extra tokens of an entry that matches several."
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
  declared_role_ids = toset([for role in pangolin_role.apps : tostring(role.id)])

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

  foreign_roles = [
    for role in try(local.roles_raw.roles, []) : {
      id   = tostring(role.roleId)
      name = role.name
    }
    if !contains(local.declared_role_ids, tostring(role.roleId))
  ]

  undeclared_roles = [
    for role in local.foreign_roles : "${role.name} (${role.id})"
    if !contains(keys(local.unmanaged_roles), role.name)
  ]

  # Same rule as for the tokens: a second role carrying an excepted name is a
  # new role, not the one that was reviewed.
  misused_role_exceptions = [
    for name in keys(local.unmanaged_roles) : name
    if length([for role in local.foreign_roles : role if role.name == name]) != 1
  ]
}

check "role_inventory" {
  assert {
    condition = (
      try(local.roles_raw.roles, null) != null
      && length(try(local.roles_raw.roles, [])) == try(local.roles_raw.pagination.total, -1)
    )
    error_message = "Could not read the full role list (HTTP ${data.http.pangolin_roles.status_code}; the API key needs the listRoles action): the role audit did not run."
  }

  assert {
    condition = length(local.undeclared_roles) == 0
    error_message = join(" ", [
      "Roles live in Pangolin that this configuration did not create:",
      "${join(", ", local.undeclared_roles)}.",
      "Either declare them (add the slug to local.apps in roles.tf, or a",
      "pangolin_role imported with `tofu import`), delete them in Pangolin, or",
      "list them in local.unmanaged_roles with the reason they stay manual.",
      "Expected once while an app is removed.",
    ])
  }

  assert {
    condition     = length(local.misused_role_exceptions) == 0
    error_message = "These entries of local.unmanaged_roles do not match exactly one live role: ${join(", ", local.misused_role_exceptions)}. Remove an entry whose role is gone; delete the duplicates of an entry that matches several."
  }
}
