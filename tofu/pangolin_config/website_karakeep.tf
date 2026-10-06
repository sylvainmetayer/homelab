# Resource, target and monitors: local.websites (websites.tf).
locals {
  karakeep_website = {
    name      = "Karakeep"
    subdomain = "keep"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "karakeep"
    backup    = true

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "karakeep"
      port    = 3000
      hc_path = "/api/health"
    }
  }
}

# The mobile app, the browser extension and the MCP server cannot go through the
# Pangolin SSO wall. Rather than letting `/api/*` bypass it, each one sends a
# Pangolin access token in its custom headers (P-Access-Token-Id /
# P-Access-Token) on top of its Karakeep API key: the API stays behind both
# the SSO wall and the geo-filter, and the mobile app's tRPC calls
# (/api/trpc), which the former `/api/v1/*` bypass never covered, get through
# too. The only paths left open are the public lists' below, none of which
# serves a private bookmark.
#
# One token per client, so a lost phone is revoked without touching the others.
# Read them with `tofu output -json karakeep_client_access_tokens`.
resource "pangolin_resource_access_token" "karakeep_clients" {
  for_each = toset(["mobile", "extension", "mcp"])

  resource_id = pangolin_resource.website["karakeep"].id
  title       = "${pangolin_resource.website["karakeep"].name} ${each.key}"
}

output "karakeep_client_access_tokens" {
  description = "KARAKEEP - En-têtes Pangolin des clients (app mobile, extension, MCP)"
  value = {
    for client, token in pangolin_resource_access_token.karakeep_clients : client => {
      "P-Access-Token-Id" = tostring(token.id)
      "P-Access-Token"    = token.token
    }
  }
  sensitive = true
}

# Public lists (list > Share > "Public list") are read by people with no
# account, wherever they are: these ACCEPTs, made by local.path_bypasses
# (rules.tf), sit in the 2 - 9 band in front of the country rules, and skip the
# SSO wall. Each path is one the
# page /public/lists/<listId> actually requests, read off the Karakeep v0.33.2
# sources (apps/web/app/public, components/public/lists, packages/api); the
# `karakeep_public_paths_follow_the_image` test fails when the image moves, so
# that they are read again. Karakeep's own authorisation still applies behind
# every one of them, so a list that is not public answers 404.
#
# Deliberately not opened: /api/auth/session (next-auth refetches it when the
# tab regains focus; failing just logs a console error), /icons/* and
# /apple-icon.png (the tab's favicon only), and anything broader under /api.
locals {
  karakeep_public_paths = {
    # The server-rendered page itself (first 20 bookmarks included). The only
    # route under /public.
    "/public/lists/*" = 2

    # Next.js build output: JS chunks, CSS, the self-hosted Inter font and the
    # logo. Same bytes for every Karakeep install.
    "/_next/static/*" = 3

    # Banner images, screenshots and attached files. Served only with a token
    # the server signs per asset when it renders the list, with an expiry.
    "/api/public/*" = 4

    # Infinite scroll past the first page, the only tRPC query the page sends.
    # Spelled out in full, no wildcard: tRPC batches calls as a comma-joined
    # list in this one segment, so `publicBookmarks.*` also matched
    # `publicBookmarks.x,apiKeys.exchange` - a password-to-API-key exchange
    # open to the whole world, without SSO or geo-filter. An exact segment
    # matches a batch of this procedure alone and nothing else.
    "/api/trpc/publicBookmarks.getPublicBookmarksInList" = 5

    # The page's RSS button. Answers for a public list, or for a private one
    # only with its rssToken in the query string.
    "/api/v1/rss/lists/*" = 6
  }
}

# Any path holding a backslash is dropped before the ACCEPTs above: see
# pangolin_resource_rule.backslash_guard in rules.tf, which covers every
# resource with a path rule.

output "karakeep_access_token" {
  description = "KARAKEEP - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["karakeep"]
  sensitive   = true
}

output "uptime_backup_karakeep_url" {
  description = "KARAKEEP - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["karakeep"]
  sensitive   = true
}
