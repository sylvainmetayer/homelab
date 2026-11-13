# ---------------------------------------------------------------------------
# Binding and hand-set authentication audit (ADR 0006, audit ex3 du 11/11).
#
# access_inventory.tf (tokens, roles), rules.tf (rules, targets) and the
# coverage audit do not read WHO is let in. Four things made in a click in the
# Pangolin UI stayed invisible to `tofu plan`:
#
#   - a role bound to a public resource (a broad role such as `bentopdf`,
#     granted to every new account, bound to Nextcloud);
#   - a user bound to a public resource or to a private one;
#   - a password, a PIN or a header auth set on a public resource;
#   - a private resource (site-resources), and its roles, users and OLM clients.
#
# The provider only compares what it declares: a binding it does not own is
# neither read nor removed, so the plan says « No changes ».
#
# Reads added by this file, per plan (ids come from the live lists, so a
# resource made by hand is audited too):
#   - 1 request for the private resources (org-wide list, pageSize=1000);
#   - 2 per public resource (roles, users): there is no org-wide endpoint;
#   - 3 per private resource (roles, users, clients), same reason;
#   - 0 for the authentication methods: GET .../resources, already read by
#     geo_rule_coverage (rules.tf), carries passwordId, pincodeId and
#     headerAuthId.
# Pangolin answers each of them from its own database, in the same way as the
# targets and rules reads of rules.tf (one request per resource as well).
#
# Public resources are compared by NAME and role id, private ones by id for the
# inventory and by name and role/client id for bindings: a name is a literal
# here, known at plan time even for a resource not created yet. A hand-made
# resource that copies a managed name would share its declared bindings: the
# coverage audit (rules.tf) is the one that sees such a duplicate.
# ---------------------------------------------------------------------------

data "http" "pangolin_site_resources" {
  url = "${local.pangolin_url}/v1/org/${local.pangolin_org_id}/site-resources?pageSize=1000"

  request_headers = {
    Authorization = "Bearer ${local.pangolin_api_key}"
    Accept        = "application/json"
  }
}

# The four per-resource endpoints below take no pagination argument and return
# the whole list (GET /resource/{id}/roles, /users and
# /site-resource/{id}/roles, /users, /clients).
data "http" "pangolin_resource_roles" {
  for_each = local.live_resource_names

  url = "${local.pangolin_url}/v1/resource/${each.key}/roles"

  request_headers = {
    Authorization = "Bearer ${local.pangolin_api_key}"
    Accept        = "application/json"
  }
}

data "http" "pangolin_resource_users" {
  for_each = local.live_resource_names

  url = "${local.pangolin_url}/v1/resource/${each.key}/users"

  request_headers = {
    Authorization = "Bearer ${local.pangolin_api_key}"
    Accept        = "application/json"
  }
}

data "http" "pangolin_site_resource_roles" {
  for_each = local.live_site_resource_names

  url = "${local.pangolin_url}/v1/site-resource/${each.key}/roles"

  request_headers = {
    Authorization = "Bearer ${local.pangolin_api_key}"
    Accept        = "application/json"
  }
}

data "http" "pangolin_site_resource_users" {
  for_each = local.live_site_resource_names

  url = "${local.pangolin_url}/v1/site-resource/${each.key}/users"

  request_headers = {
    Authorization = "Bearer ${local.pangolin_api_key}"
    Accept        = "application/json"
  }
}

data "http" "pangolin_site_resource_clients" {
  for_each = local.live_site_resource_names

  url = "${local.pangolin_url}/v1/site-resource/${each.key}/clients"

  request_headers = {
    Authorization = "Bearer ${local.pangolin_api_key}"
    Accept        = "application/json"
  }
}

locals {
  # Id -> name of what Pangolin holds. The ids are strings: they are the
  # for_each keys, and the URL takes them as they are.
  live_resource_names = { for resource in local.pangolin_live_raw.resources : tostring(resource.resourceId) => resource.name }

  live_site_resources_raw = try(jsondecode(data.http.pangolin_site_resources.response_body).data.siteResources, null)

  live_site_resource_names = { for resource in coalesce(local.live_site_resources_raw, []) : tostring(resource.siteResourceId) => resource.name }

  # HCL cannot enumerate the private resources: a new pangolin_site_resource has
  # to be added here, or the audit reports it as undeclared (loudly, on purpose).
  declared_site_resource_ids = toset([
    for resource in [
      pangolin_site_resource.app_proxy,
      pangolin_site_resource.nas_web,
      pangolin_site_resource.printer,
      pangolin_site_resource.docker_apps,
      pangolin_site_resource.pi,
      pangolin_site_resource.proxmox,
      pangolin_site_resource.nas,
      pangolin_site_resource.dns,
      pangolin_site_resource.flip,
      pangolin_site_resource.jellyfin,
      pangolin_site_resource.mediamanager,
      pangolin_site_resource.prowlarr,
      pangolin_site_resource.qbittorrent,
      pangolin_site_resource.vpn,
      pangolin_site_resource.vpn_flip,
    ] : tostring(resource.id)
  ])

  # What this configuration binds, as "<resource name>|<role or client id>".
  # Admin is attached by Pangolin itself and never listed. No user is declared
  # anywhere (the household's accounts are made in Pangolin, or by the IdP): any
  # user bound to a resource is reported.
  declared_resource_role_pairs = toset(concat(
    [for key, binding in pangolin_resource_role.website : "${pangolin_resource.website[key].name}|${binding.role_id}"],
    [for key, binding in pangolin_resource_role.remote_desktop : "${pangolin_resource.remote_desktop[key].name}|${binding.role_id}"],
  ))

  declared_site_resource_role_pairs = toset([
    "${pangolin_site_resource.jellyfin.name}|${pangolin_site_resource_role.jellyfin.role_id}",
    "${pangolin_site_resource.mediamanager.name}|${pangolin_site_resource_role.mediamanager.role_id}",
    "${pangolin_site_resource.prowlarr.name}|${pangolin_site_resource_role.prowlarr.role_id}",
    "${pangolin_site_resource.qbittorrent.name}|${pangolin_site_resource_role.qbittorrent.role_id}",
  ])

  declared_site_resource_client_pairs = toset([
    "${pangolin_site_resource.docker_apps.name}|${pangolin_site_resource_client.docker_apps_ci.client_id}",
    "${pangolin_site_resource.pi.name}|${pangolin_site_resource_client.pi_ci.client_id}",
    "${pangolin_site_resource.vpn_flip.name}|${pangolin_site_resource_client.vpn_flip_ci_plan.client_id}",
  ])

  # Authentication methods set on a public resource, by resource id (the ids of
  # GET .../resources). No password is declared.
  declared_password_resource_ids    = toset([])
  declared_pincode_resource_ids     = toset([for pin in [pangolin_resource_pincode.immich, pangolin_resource_pincode.flip_planning, pangolin_resource_pincode.neonova, pangolin_resource_pincode.neonova_aide] : tostring(pin.resource_id)])
  declared_header_auth_resource_ids = toset([tostring(pangolin_resource_header_auth.grocy_mobile.resource_id)])

  # An audit that silently sees nothing is worse than no audit: a response that
  # does not decode into its list is reported, never read as an empty one (same
  # reasoning as failed_target_lookups in rules.tf).
  binding_reads = {
    "roles of public resource"    = { responses = { for id, r in data.http.pangolin_resource_roles : id => { body = r.response_body, status = r.status_code } }, field = "roles", names = local.live_resource_names }
    "users of public resource"    = { responses = { for id, r in data.http.pangolin_resource_users : id => { body = r.response_body, status = r.status_code } }, field = "users", names = local.live_resource_names }
    "roles of private resource"   = { responses = { for id, r in data.http.pangolin_site_resource_roles : id => { body = r.response_body, status = r.status_code } }, field = "roles", names = local.live_site_resource_names }
    "users of private resource"   = { responses = { for id, r in data.http.pangolin_site_resource_users : id => { body = r.response_body, status = r.status_code } }, field = "users", names = local.live_site_resource_names }
    "clients of private resource" = { responses = { for id, r in data.http.pangolin_site_resource_clients : id => { body = r.response_body, status = r.status_code } }, field = "clients", names = local.live_site_resource_names }
  }

  binding_lookup_failures = flatten([
    for what, read in local.binding_reads : [
      for id, response in read.responses :
      "${what} ${read.names[id]} (HTTP ${response.status})"
      if try(jsondecode(response.body).data[read.field], null) == null
    ]
  ])

  # The list of private resources is the only paged one: truncated when it does
  # not hold `pagination.total` entries, or says nothing about it.
  site_resources_truncated = local.live_site_resources_raw != null && try(
    length(local.live_site_resources_raw) != jsondecode(data.http.pangolin_site_resources.response_body).data.pagination.total,
    true
  )

  # One row per binding, whatever its kind: `key` is compared with the declared
  # pairs, `admin` marks the built-in role that is never declared.
  live_resource_role_bindings = flatten([
    for id, response in data.http.pangolin_resource_roles : [
      for role in try(jsondecode(response.response_body).data.roles, []) : {
        key   = "${local.live_resource_names[id]}|${role.roleId}"
        label = "${local.live_resource_names[id]} <- role ${role.roleId} (${role.name})"
        admin = tostring(role.roleId) == "1" || try(role.isAdmin == true, false)
      }
    ]
  ])

  live_site_resource_role_bindings = flatten([
    for id, response in data.http.pangolin_site_resource_roles : [
      for role in try(jsondecode(response.response_body).data.roles, []) : {
        key   = "${local.live_site_resource_names[id]}|${role.roleId}"
        label = "${local.live_site_resource_names[id]} <- role ${role.roleId} (${role.name})"
        admin = tostring(role.roleId) == "1" || try(role.isAdmin == true, false)
      }
    ]
  ])

  live_site_resource_client_bindings = flatten([
    for id, response in data.http.pangolin_site_resource_clients : [
      for client in try(jsondecode(response.response_body).data.clients, []) : {
        key   = "${local.live_site_resource_names[id]}|${client.clientId}"
        label = "${local.live_site_resource_names[id]} <- client ${client.clientId} (${client.name})"
      }
    ]
  ])

  live_user_bindings = concat(
    flatten([
      for id, response in data.http.pangolin_resource_users : [
        for user in try(jsondecode(response.response_body).data.users, []) :
        "${local.live_resource_names[id]} <- user ${user.userId} (${user.username})"
      ]
    ]),
    flatten([
      for id, response in data.http.pangolin_site_resource_users : [
        for user in try(jsondecode(response.response_body).data.users, []) :
        "${local.live_site_resource_names[id]} <- user ${user.userId} (${user.username})"
      ]
    ]),
  )

  undeclared_resource_roles = [
    for binding in local.live_resource_role_bindings : binding.label
    if !binding.admin && !contains(local.declared_resource_role_pairs, binding.key)
  ]

  undeclared_site_resource_roles = [
    for binding in local.live_site_resource_role_bindings : binding.label
    if !binding.admin && !contains(local.declared_site_resource_role_pairs, binding.key)
  ]

  undeclared_site_resource_clients = [
    for binding in local.live_site_resource_client_bindings : binding.label
    if !contains(local.declared_site_resource_client_pairs, binding.key)
  ]

  undeclared_site_resources = [
    for id, name in local.live_site_resource_names : "${id} (${name})"
    if !contains(local.declared_site_resource_ids, id)
  ]

  # The list of public resources must still carry the three ids: should a
  # Pangolin upgrade drop them, the audit below would read « none » everywhere.
  resources_without_auth_ids = [
    for resource in local.pangolin_live_raw.resources : resource.name
    if !can(resource.passwordId) || !can(resource.pincodeId) || !can(resource.headerAuthId)
  ]

  # `passwordId` & co. are the effective ids (the resource's own, or its shared
  # policy's: resource_policy_id is pinned to 0 in resource_defaults.tf).
  undeclared_resource_auth = flatten([
    for resource in local.pangolin_live_raw.resources : concat(
      try(resource.passwordId, null) != null && !contains(local.declared_password_resource_ids, tostring(resource.resourceId)) ? ["${resource.name}: password"] : [],
      try(resource.pincodeId, null) != null && !contains(local.declared_pincode_resource_ids, tostring(resource.resourceId)) ? ["${resource.name}: PIN"] : [],
      try(resource.headerAuthId, null) != null && !contains(local.declared_header_auth_resource_ids, tostring(resource.resourceId)) ? ["${resource.name}: header auth"] : [],
    )
  ])
}
