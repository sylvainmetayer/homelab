# Resource, target and monitors: local.websites (websites.tf).
#
# No health route in the image: the favicon is a static file served by the
# Node server, behind the image's own Caddy (port 3280), so a 200 there proves
# both are up. `/` and `/login` answer a redirect (setup wizard, login), which
# the probe's hc_status = 200 would count as a failure.
locals {
  wishlist_website = {
    name      = "Wishlist"
    subdomain = "cadeaux"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "wishlist"
    backup    = true

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "wishlist"
      port    = 3280
      hc_path = "/favicon.ico"
    }
  }
}

# Public lists (list > Share, once the group's admin allows public lists) are
# opened by the family with no account, through a link sent by message:
# these ACCEPTs, made by local.path_bypasses (rules.tf), sit in the 2 - 9 band
# in front of the country rules and skip the SSO wall. Each path is one the
# page /lists/<listId> actually requests, read off the Wishlist v0.68.0
# sources (src/routes/lists/[id], src/routes/api, src/lib/api, Caddyfile).
# The list id is a cuid: it is the link's only secret, and Wishlist checks
# `list.public` behind every path below, so a list that is not public
# redirects to /login (behind the SSO) or answers 404.
#
# Deliberately not opened:
# - /login, /signup, /setup-wizard and the rest of the app: the couple goes
#   through the SSO, the family never needs an account.
# - /api/claims/*: un-claiming or marking as purchased requires a Wishlist
#   session (requireLoginOrError) - a public claim cannot be undone by the
#   guest anyway (README, "Registry Mode").
# - The PWA (manifest.webmanifest, registerSW.js, sw.js, workbox-*.js) and the
#   favicons: the page works without them; only the couple installs the app.
locals {
  wishlist_public_paths = {
    # The server-rendered page, its __data.json (reloaded after a claim) and
    # its /events SSE stream. Also covers /lists/create, /lists/<id>/manage and
    # /lists/<id>/create-item, which all call requireLogin() and redirect to
    # /login, behind the SSO.
    "/lists/*" = 2

    # SvelteKit build output (immutable JS/CSS chunks, env.js, version.json):
    # the same bytes for every Wishlist install.
    "/_app/*" = 3

    # The font the page preloads.
    "/fonts/*" = 3

    # Item images (and avatars), served straight from uploads/ by the image's
    # Caddy, without any check: the file names are `<slug>-<timestamp>.webp`.
    # Without them a public list shows no picture. They are 300 px product
    # thumbnails; an avatar is only uploaded if someone chooses to.
    "/api/assets/*" = 4

    # A public claim, in two calls: the guest's identifier (POST, creates a
    # name/e-mail SystemUser row that opens no session and no access), then
    # the claim itself (PUT, refused with 404 unless the list is public). The
    # other routes under /api/lists/* (list and item edits) stay closed.
    "/api/users/public"           = 5
    "/api/lists/*/items/*/claims" = 5
  }
}

# Any path holding a backslash is dropped before the ACCEPTs above: see
# pangolin_resource_rule.backslash_guard in rules.tf, which covers every
# resource with a path rule.

output "wishlist_access_token" {
  description = "WISHLIST - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["wishlist"]
  sensitive   = true
}

output "uptime_backup_wishlist_url" {
  description = "WISHLIST - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["wishlist"]
  sensitive   = true
}
