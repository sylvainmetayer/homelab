# ---------------------------------------------------------------------------
# Access token and role inventory audit.
#
# The same question as terraform_data.rule_inventory (rules.tf), on the two
# other things the Pangolin UI makes in a click and `tofu plan` never sees:
#
#   - an access token lets whoever holds it past the SSO wall of its resource,
#     for good (none here expires). A token made by hand is a standing way in
#     that no file of this repository mentions;
#   - a role is what a user or an IdP mapping is granted; one made by hand can
#     be bound to resources from the UI just as silently.
#
# Every token and every role Pangolin holds must be one this configuration
# created, compared on ids, or one of the exceptions below, each with its
# reason. Both lists are org-wide: one request each.
# ---------------------------------------------------------------------------

# GET /v1/org/{org}/access-tokens takes `limit`/`offset`, not `pageSize`, and
# its `pagination.total` is not the length of the list (23 for 30 tokens on
# 2026-10-28), so a truncated list is the one that fills the page instead.
data "http" "pangolin_access_tokens" {
  url = "${local.pangolin_url}/v1/org/${local.pangolin_org_id}/access-tokens?limit=${local.access_token_page_limit}"

  request_headers = {
    Authorization = "Bearer ${local.pangolin_api_key}"
    Accept        = "application/json"
  }
}

# This one takes `pageSize` (and rejects `limit`), and defaults to 20.
data "http" "pangolin_roles" {
  url = "${local.pangolin_url}/v1/org/${local.pangolin_org_id}/roles?pageSize=1000"

  request_headers = {
    Authorization = "Bearer ${local.pangolin_api_key}"
    Accept        = "application/json"
  }
}

locals {
  access_token_page_limit = 1000

  # Live, made by hand, kept on purpose or pending a decision. Keyed by id
  # (`accessTokenId` / `roleId`), never by title or name: two tokens can share
  # a title, and a renamed role keeps its id. An entry leaves this list the day
  # its token or role is deleted in Pangolin (check.inventory_exceptions_stale
  # says so) or declared here.
  unmanaged_access_tokens = {
    # Flip Planning, title "MCP ". The production planning only shows it to
    # its admins on its MCP page (prod_planning_mcp_pangolin_access_token* in
    # ansible/secrets.sops.yaml): /mcp/* already answers without SSO through
    # local.flip_planning_mcp_paths, so no MCP client needs it, while it opens
    # the whole planning to whoever holds it. The demo dropped its own in #763.
    # Decision pending (#525): delete it and empty the two prod variables.
    "3nexu81w" = "Flip Planning \"MCP\": hand-made, decision pending (#525)"

    # Immich, title "todo wip", made by hand on 2026-07-11; nothing in this
    # repository or in the Immich role reads it. Decision pending (#525):
    # delete it unless a client still sends it.
    "jup2pfkh" = "Immich \"todo wip\": hand-made, decision pending (#525)"
  }

  unmanaged_roles = {
    # Made by Pangolin with the org; neither can be deleted.
    "1" = "Admin: built in"
    "2" = "Member: built in"

    # "Rôle par défaut pour l'OIDC", made by hand: on 2026-10-28 no user holds
    # it, no resource or private resource is bound to it and no IdP has an org
    # policy (`orgCount` 0 on both). Decision pending (#525): delete it.
    "5" = "Restreint: hand-made, decision pending (#525)"
  }

  # Every token and role resource of this configuration. HCL cannot enumerate
  # them, so a new pangolin_resource_access_token or pangolin_role has to be
  # added here or the audit reports it as undeclared - loudly, on purpose.
  declared_access_token_ids = toset(concat(
    [for token in pangolin_resource_access_token.healthcheck : tostring(token.id)],
    [for token in pangolin_resource_access_token.beszel_agents : tostring(token.id)],
    [for token in pangolin_resource_access_token.karakeep_clients : tostring(token.id)],
    [for token in pangolin_resource_access_token.trek_mcp_clients : tostring(token.id)],
  ))

  declared_role_ids = toset(concat(
    [for role in pangolin_role.apps : tostring(role.id)],
    [tostring(pangolin_role.jellyfin.id)],
  ))

  # null when the response does not decode: reported below, never read as an
  # empty list (same reasoning as failed_target_lookups in rules.tf).
  live_access_tokens_raw = try(jsondecode(data.http.pangolin_access_tokens.response_body).data.accessTokens, null)
  live_roles_raw         = try(jsondecode(data.http.pangolin_roles.response_body).data.roles, null)

  live_access_tokens = [
    for token in coalesce(local.live_access_tokens_raw, []) : {
      id    = tostring(token.accessTokenId)
      label = "${token.accessTokenId} (\"${coalesce(try(token.title, null), "")}\" on ${coalesce(try(token.resourceName, null), "an unnamed resource")})"
    }
  ]

  live_roles = [
    for role in coalesce(local.live_roles_raw, []) : {
      id    = tostring(role.roleId)
      label = "${role.roleId} (${role.name})"
    }
  ]

  inventory_lookup_failures = concat(
    local.live_access_tokens_raw == null ? ["access tokens (HTTP ${data.http.pangolin_access_tokens.status_code})"] : [],
    local.live_roles_raw == null ? ["roles (HTTP ${data.http.pangolin_roles.status_code})"] : [],
  )

  # A role list without `pagination.total` counts as truncated, not complete.
  inventory_truncated_lists = concat(
    length(local.live_access_tokens) >= local.access_token_page_limit ? ["access tokens"] : [],
    local.live_roles_raw != null && try(
      length(local.live_roles) != jsondecode(data.http.pangolin_roles.response_body).data.pagination.total,
      true
    ) ? ["roles"] : [],
  )

  undeclared_access_tokens = [
    for token in local.live_access_tokens : token.label
    if !contains(local.declared_access_token_ids, token.id) && !contains(keys(local.unmanaged_access_tokens), token.id)
  ]

  undeclared_roles = [
    for role in local.live_roles : role.label
    if !contains(local.declared_role_ids, role.id) && !contains(keys(local.unmanaged_roles), role.id)
  ]

  # Exceptions that match nothing live any more: the token or role is gone.
  # Only on complete lists: a page missing would make every exception on it
  # look stale, on top of the precondition that already stops the plan.
  stale_inventory_exceptions = length(local.inventory_lookup_failures) + length(local.inventory_truncated_lists) > 0 ? [] : concat(
    [for id in keys(local.unmanaged_access_tokens) : "access token ${id}" if !contains([for token in local.live_access_tokens : token.id], id)],
    [for id in keys(local.unmanaged_roles) : "role ${id}" if !contains([for role in local.live_roles : role.id], id)],
  )
}

resource "terraform_data" "access_inventory" {
  input = length(local.live_access_tokens) + length(local.live_roles)

  lifecycle {
    precondition {
      condition = length(local.inventory_lookup_failures) == 0
      error_message = join(" ", [
        "Could not read the Pangolin",
        "${join(", ", local.inventory_lookup_failures)}.",
        "The audit below cannot run, so the plan is stopped rather than passing on no data.",
      ])
    }

    precondition {
      condition = length(local.inventory_truncated_lists) == 0
      error_message = join(" ", [
        "Pangolin returned a truncated list of",
        "${join(", ", local.inventory_truncated_lists)}.",
        "The audit below would not see the missing entries, so it is meaningless.",
      ])
    }

    precondition {
      condition = length(local.undeclared_access_tokens) == 0
      error_message = join(" ", [
        "Access tokens live in Pangolin that this configuration did not create:",
        "${join(", ", local.undeclared_access_tokens)}.",
        "Either declare them (a pangolin_resource_access_token, plus its line in",
        "local.declared_access_token_ids), delete them in Pangolin, or list them",
        "in local.unmanaged_access_tokens (access_inventory.tf) with the reason.",
      ])
    }

    precondition {
      condition = length(local.undeclared_roles) == 0
      error_message = join(" ", [
        "Roles live in Pangolin that this configuration did not create:",
        "${join(", ", local.undeclared_roles)}.",
        "Either declare them (a pangolin_role, plus its line in",
        "local.declared_role_ids), delete them in Pangolin, or list them in",
        "local.unmanaged_roles (access_inventory.tf) with the reason.",
      ])
    }
  }
}

# Only a reminder, like travel_countries_stale: a stale exception opens
# nothing, it is dead weight that says something still exists.
check "inventory_exceptions_stale" {
  assert {
    condition     = length(local.stale_inventory_exceptions) == 0
    error_message = "Exceptions of access_inventory.tf that match nothing live in Pangolin, to remove: ${join(", ", local.stale_inventory_exceptions)}."
  }
}
