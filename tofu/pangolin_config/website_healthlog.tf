# Resource, target and monitors: local.websites (websites.tf).
#
# Health data: behind the SSO wall and the country rules like every resource,
# then HealthLog's own login. One path open without the SSO, the Withings
# notifications (healthlog_withings_webhook_paths below); no access token
# (ansible/roles/healthlog/README.md, « Accès »):
#
# - Withings OAuth callback (/api/withings/callback): a top-level GET
#   redirect from withings.com in the user's own browser, which carries the
#   Pangolin session cookie (SameSite=Lax, server/auth/sessions/resource.ts of
#   Pangolin 1.25.3), so it passes the SSO like any other page. Not opened.
# - Phone: the PWA in the mobile browser logs in through the SSO like the
#   desktop one; a `?p_token=` link would only set the same session cookie
#   (HealthLog's manifest start_url drops the query), so no access token.

locals {
  healthlog_website = {
    name      = "HealthLog"
    subdomain = "sante"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "healthlog"
    backup    = true
    # `/` redirects to the login page (src/proxy.ts): the page it lands on,
    # one request per probe instead of two.
    monitor_path = "/auth/login"

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      title       = "Santé"
      group       = "Vie perso"
      description = "Poids, tension, sommeil, bilans (HealthLog)"
      icon        = "mdi-heart-pulse"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "healthlog"
      port    = 3000
      hc_path = "/api/health"
    }
  }
}

output "uptime_backup_healthlog_url" {
  description = "HEALTHLOG - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["healthlog"]
  sensitive   = true
}

# Withings notifications, server to server from Withings' own servers, so
# from anywhere and without any session: an ACCEPT made by
# local.path_bypasses (rules.tf), in the 2 - 9 band in front of the country
# rules. Read off the HealthLog 1.46.5 sources:
# src/app/api/withings/webhook/[token]/route.ts and src/lib/withings/sync.ts
# (getWithingsWebhookCallbackUrl, the URL handed to Withings' Notify.subscribe).
#
# - URL: /api/withings/webhook/<WITHINGS_WEBHOOK_SECRET>, the secret a
#   sha256 of backup_passphrase (64 hex characters, role defaults), compared
#   in constant time by every verb; 401 without it. Withings signs nothing
#   and sends no header, the secret in the path is the only check.
# - HEAD and GET: Withings' verification of the URL when HealthLog
#   subscribes (at the OAuth callback, then retried hourly with a backoff):
#   200 or 401, nothing else. POST: the notification itself (user id,
#   category, time range); HealthLog then fetches the readings from the
#   Withings API with the stored token, the body is never trusted as data.
#   All three share one rate limit (applyWebhookRateLimit).
#
# The segment glob `**` matches exactly one non-empty segment
# (server/lib/pathMatch.ts, Pangolin 1.25.3: only a bare `*` segment spans
# zero or more segments, a segment holding a `*` is a glob on one segment;
# `?` is refused by the rule validator). So the rule never matches
# /api/withings/webhook itself (HealthLog's legacy `?secret=` route), nor
# anything deeper, nor /api/withings/callback, /connect, /credentials,
# /disconnect, /status or /sync, which stay behind the SSO. `..`, `%2e%2e`
# and `%2F` are resolved before matching; a backslash is dropped first by
# the backslash guard (rules.tf).
locals {
  healthlog_withings_webhook_paths = {
    "/api/withings/webhook/**" = 2
  }
}
