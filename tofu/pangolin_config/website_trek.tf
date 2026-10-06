# Resource, target and monitors: local.websites (websites.tf).
locals {
  trek_website = {
    name      = "TREK"
    subdomain = "travels"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "trek"
    backup    = true

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "trek"
      port    = 3000
      hc_path = "/api/health"
    }
  }
}

# Created by hand in the Pangolin UI and declared here so LIVE and code agree.
# Same pattern as `pangolin_resource_rule.immich_home_ip`: the home connection
# is allowed in by IP regardless of the geo rules.
#
# Priority 9: the last slot before the `PASS COUNTRY` rules generated in
# rules.tf (FR at 10, DE at 11). It used to sit at 12, just behind them, where
# it was never reached: the home connection is French, so the FR PASS matched
# first and sent it to the SSO wall like anybody else. Ahead of the country
# rules it does what it says - the home connection gets in by IP, without
# SSO. Only the backslash DROP of rules.tf (priority 1) comes before it.
resource "pangolin_resource_rule" "trek_home_ip" {
  resource_id = pangolin_resource.website["trek"].id
  action      = "ACCEPT"
  match       = "IP"
  value       = local.home_ip
  priority    = 9
  enabled     = true
}

# MCP server (Settings > Integrations > MCP), driven by hosted assistants
# (Claude.ai and its mobile app, ChatGPT...) from their own servers, in the US
# for Claude: the catch-all `DROP COUNTRY ALL` (rules.tf) drops them before any
# authentication runs, access token included - Pangolin evaluates the rules
# first (server/routers/badger/verifySession.ts). Read off the TREK v4.3.3
# sources (server/src/nest/{mcp-transport,oauth,platform}).
#
# Two kinds of paths, two treatments, all in the 2 - 9 band of rules.tf and all
# exact - no wildcard, so neither `..` (resolved by Pangolin) nor `\` (left
# as is) can turn one of them into a prefix of something else.
#
# 1. `/mcp` itself: PASS, not ACCEPT. PASS ends the rule walk - the country
#    rules are never reached - but still sends the request through Pangolin's
#    authentication: an SSO session, or one of the access tokens below, as
#    headers (P-Access-Token-Id / P-Access-Token) or in the URL
#    (`?p_token=<id>.<token>`, for Claude.ai, which takes no custom header).
#    TREK then demands its own OAuth bearer on top. Without a token the
#    request never reaches TREK.
#
# 2. OAuth's public surface, ACCEPT, through local.path_bypasses (rules.tf):
#    what an assistant's server calls without any session and without the
#    token, since it builds those URLs from the discovery documents, not from
#    the connector URL. The discovery documents (static JSON: issuer,
#    endpoints, scopes) and the token endpoint (PKCE code or refresh token,
#    plus client secret, rate-limited by TREK).
#
# Deliberately not opened: /oauth/authorize and /oauth/consent (the user's own
# browser, which has the SSO session), /oauth/register (dynamic client
# registration: create the client beforehand in TREK, Claude.ai preset, and
# give its id and secret to the connector), /oauth/revoke and /oauth/userinfo.
#
# Exact paths, pairwise disjoint and disjoint from `/mcp`: their order does not
# matter, hence one shared priority.
locals {
  trek_mcp_public_paths = {
    # Discovery. The first is the one TREK's 401 points to
    # (WWW-Authenticate resource_metadata); the others are where other clients
    # look first - flat RFC 9728, RFC 8414 with and without the resource path,
    # OIDC, and the same three under the server address.
    "/.well-known/oauth-protected-resource/mcp"   = 2
    "/.well-known/oauth-protected-resource"       = 2
    "/.well-known/oauth-authorization-server"     = 2
    "/.well-known/oauth-authorization-server/mcp" = 2
    "/.well-known/openid-configuration"           = 2
    "/mcp/.well-known/oauth-protected-resource"   = 2
    "/mcp/.well-known/oauth-authorization-server" = 2
    "/mcp/.well-known/openid-configuration"       = 2

    # Code exchange and refresh, server to server.
    "/oauth/token" = 2
  }
}

# Matches `/mcp` and `/mcp/` (Pangolin drops empty segments), nothing under it.
# Also overrides trek_home_ip for this path: from home, an MCP client needs the
# token too.
resource "pangolin_resource_rule" "trek_mcp" {
  resource_id = pangolin_resource.website["trek"].id
  action      = "PASS"
  match       = "PATH"
  value       = "/mcp"
  priority    = 3
  enabled     = true
}

# Public share links, opened worldwide without SSO through
# local.path_bypasses (rules.tf). Read off the TREK v4.3.3 sources and the
# client the pinned image ships (/app/server/public); re-read them when the
# image moves.
#
# - Trip share, `/shared/<token>`: 24 random bytes, 90-day expiry, checked by
#   every handler (share.service.ts, share.controller.ts).
# - Journey share, `/public/journey/<token>` - the post-trip album: 24 random
#   bytes, no expiry (revoked by deleting it), gallery flag and photo ownership
#   checked per request (journey-share.service.ts). Immich and Synology photos
#   are fetched by TREK server-side with the owner's credentials, so Immich
#   itself stays closed.
#
# Both pages are the SPA: Express answers index.html for any unmatched GET, so
# the page routes need no shell path of their own beyond the build files.
#
# Deliberately not opened:
# - /uploads/journey/*: the public JSON carries each photo's file path, so
#   direct file URLs would keep answering after the share is revoked. Costs an
#   uploaded journey cover, drawn at 15% opacity.
# - /uploads/avatars/*: only for a shared trip chat.
# - The PWA (registerSW.js, sw.js, workbox-*.js and its ~500 precached files):
#   the page works without the service worker, whose install fails as a whole
#   if any precached file is refused.
# - /api/auth/app-config and /api/health: called by every page, they fail
#   silently on share pages (isAuthPublicPath).
# - Trip and collection invitations, Vacay: they need a TREK account, which no
#   path rule can give.
locals {
  trek_share_paths = {
    # Build files shared by every page, the logged-in app included: entry,
    # chunks, CSS, i18n, fonts, the maplibre RTL plugin, the Plyr sprite.
    "/assets/*"                           = 4
    "/theme-boot.js"                      = 4
    "/shell-guard.js"                     = 4
    "/icons/icon.svg"                     = 4
    "/icons/icon-white.svg"               = 4
    "/icons/apple-touch-icon-180x180.png" = 4

    # Trip share: page, data, place thumbnails (placeId may hold `%2F`, hence
    # the trailing `*`).
    "/shared/*"     = 4
    "/api/shared/*" = 4

    # Journey share: page, data, every photo and video
    # (/api/public/journey/<token>/photos/<id>/thumbnail|original).
    "/public/journey/*"     = 4
    "/api/public/journey/*" = 4

    # Trip covers (also the journey hero when it comes from the trip) and
    # uploaded place images. No token: Express serves them to anyone holding
    # the UUID file name (platform.routes.ts), here worldwide - and, like
    # /uploads/journey/* below, a URL handed out by a share keeps answering
    # after that share is revoked or expires. Accepted here and not there:
    # these are the trip's cover and its places' pictures, without which the
    # shared trip renders as bare text, whereas the journey uploads are the
    # trip's own photo album, and the journey page still works without them
    # (photos go through /api/public/journey/*, which checks the token on
    # every request).
    "/uploads/covers/*" = 4
    "/uploads/places/*" = 4
  }
}

# One token per client, so one is revoked without touching the others.
# `persist_session` is left to Pangolin's default (false), and that matters for
# the `?p_token=` form: with a persisted session, Badger answers a GET carrying
# the token with a cookie and a redirect to the same URL without it, which a
# server-side MCP client (no cookie jar) follows straight into the SSO wall -
# the GET /mcp stream would never open.
#
# Read them with `tofu output -json trek_mcp_client_access_tokens`.
resource "pangolin_resource_access_token" "trek_mcp_clients" {
  for_each = toset(["claude-ai", "claude-code"])

  resource_id = pangolin_resource.website["trek"].id
  title       = "${pangolin_resource.website["trek"].name} MCP ${each.key}"
}

output "trek_mcp_client_access_tokens" {
  description = "TREK - Accès Pangolin au MCP : en-têtes, ou URL de connecteur (Claude.ai)"
  value = {
    for client, token in pangolin_resource_access_token.trek_mcp_clients : client => {
      headers = {
        "P-Access-Token-Id" = tostring(token.id)
        "P-Access-Token"    = token.token
      }
      connector_url = "https://${pangolin_resource.website["trek"].full_domain}/mcp?p_token=${token.id}.${token.token}"
    }
  }
  sensitive = true
}

output "trek_access_token" {
  description = "TREK - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["trek"]
  sensitive   = true
}

output "uptime_backup_trek_url" {
  description = "TREK - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["trek"]
  sensitive   = true
}
