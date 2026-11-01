# Resource, target and monitors: local.websites (websites.tf).
#
# Health data: behind the SSO wall and the country rules like every resource,
# then HealthLog's own login. No path rule, no access token
# (ansible/roles/healthlog/README.md, « Accès »):
#
# - Withings OAuth callback (/api/withings/callback): a top-level GET
#   redirect from withings.com in the user's own browser, which carries the
#   Pangolin session cookie (SameSite=Lax, server/auth/sessions/resource.ts of
#   Pangolin 1.25.3), so it passes the SSO like any other page.
# - Withings notifications (/api/withings/webhook/<secret>), server to server:
#   deliberately not opened. Withings checks the URL (HEAD/GET) when HealthLog
#   subscribes, gets the SSO redirect, and HealthLog retries the subscription
#   with a backoff capped at one day; readings still arrive through its
#   hourly pull (measurements at :00, sleep at :15). Opening it would be an
#   ACCEPT of the exact prefix `/api/withings/webhook/*` through
#   local.path_bypasses, worldwide, guarded by the 64-hex secret segment.
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
