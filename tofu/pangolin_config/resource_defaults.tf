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
# `mode` is optional+computed as well, but with a provider-side default of
# "http", so leaving it out never plans as unknown: five resources declared it
# and sixteen did not, with the same result. It is pinned for a different
# reason - it is RequiresReplace, so a change of that default in a provider
# upgrade would plan a destroy and recreate of every resource that relied on
# it, new id, new rules and new access tokens included. Declared everywhere, it
# can only change here.
#
# A resource that has to differ from a pin overrides it with a literal and says
# why next to it: Gramps' `enabled = false` is the only one.
# ---------------------------------------------------------------------------

locals {
  resource_pins = {
    mode                    = "http"
    ssl                     = true
    enabled                 = true
    block_access            = false
    email_whitelist_enabled = false
    sticky_session          = false
  }
}
