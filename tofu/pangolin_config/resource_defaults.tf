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
# ---------------------------------------------------------------------------

locals {
  resource_pins = {
    ssl                     = true
    enabled                 = true
    block_access            = false
    email_whitelist_enabled = false
    sticky_session          = false
  }
}
