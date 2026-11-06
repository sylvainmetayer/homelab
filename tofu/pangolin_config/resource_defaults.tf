# ---------------------------------------------------------------------------
# Pinned optional+computed attributes.
#
# `ssl`, `enabled`, `block_access`, `email_whitelist_enabled` and
# `sticky_session` are optional+computed on pangolin_resource. Left undeclared
# they mean "accept whatever the API returns", so they plan as "(known after
# apply)" on every update and a plan can never disagree with the server. That is
# the same shape that left hc_scheme NULL on gramps and scanopy and served "no
# available server" for weeks while `tofu plan` reported "No changes".
#
# It stayed invisible as long as nothing updated these resources. Declaring the
# maintenance page does update all sixteen of them at once, which is exactly
# when an unpinned `ssl` or `enabled` is free to come back false.
#
# Values read from GET /v1/resource/{id} on 2026-08-31: identical across all
# sixteen managed resources.
#
# `tls_server_name` is optional+computed too but Pangolin holds null for it
# everywhere, and a null cannot be pinned - writing `= null` means "unset", which
# is what leaves it computed in the first place. It stays "(known after apply)"
# on updates. It only names the SNI to present upstream, so it cannot silently
# take a site down the way `enabled` can.
#
# `set_host_header`, `post_auth_path` and `maintenance_estimated_time` are
# null everywhere too (`skip_to_idp_id` is set on every SSO resource since
# 2026-11-06, websites.tf), so they cannot be pinned
# either, and a plan stays blind to a value set in the UI. `pam_mode`,
# `auth_daemon_mode`, `auth_daemon_port` and `proxy_port` do not apply to
# `mode = "http"`.
#
# `protocol` is optional+computed too, but deprecated and left undeclared on
# purpose: the fork derives it from `mode`, and Pangolin neither stores nor
# returns it for an http resource (checked on the live API on 2026-11-05), so
# Traefik never reads it and it cannot hide an outage.
#
# `mode` is optional+computed as well, but with a provider-side default of
# "http", so leaving it out never plans as unknown: five resources declared it
# and sixteen did not, with the same result. It is pinned for a different
# reason - it is RequiresReplace, so a change of that default in a provider
# upgrade would plan a destroy and recreate of every resource that relied on
# it, new id, new rules and new access tokens included. Declared everywhere, it
# can only change here.
#
# `resource_policy_id = 0` means "no shared policy": a policy attached in the UI
# wipes the resource's rules and grants, so it must show in a plan. Left unset it
# would keep whatever is attached, silently. `ai_provider_ids` cannot be declared
# outside `mode = "inference"`.
#
# They are applied once, by pangolin_resource.website (websites.tf). A resource
# that has to differ from a pin says so in its local.websites entry, with the
# reason next to it; `enabled` is the only pin an entry can override, to pause
# an app (paperless today).
# ---------------------------------------------------------------------------

locals {
  resource_pins = {
    resource_policy_id      = 0
    mode                    = "http"
    ssl                     = true
    enabled                 = true
    block_access            = false
    email_whitelist_enabled = false
    sticky_session          = false
  }
}
