# Resource, target and monitors: local.websites (websites.tf).
#
# ntfy: push notifications of the homelab (role ntfy, Docker VM). The web
# interface stays behind the SSO, then ntfy's own login; the phone apps and
# the publishers get through the paths below, with ntfy's own credentials.
locals {
  ntfy_website = {
    name      = "ntfy"
    subdomain = "ntfy"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "ntfy"
    backup    = true

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Administration"
      description = "Notifications push du homelab"
      icon        = "ntfy"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "ntfy"
      port    = 8080
      # Answers {"healthy":true} without an account, deny-all or not.
      hc_path = "/v1/health"
    }
  }

  # The topics the producers publish to, one each (ntfy_publishers in
  # ansible/roles/ntfy/defaults/main.yml, compared by the
  # `ntfy_topics_match_the_role` test). Sylvain reads all of them.
  ntfy_publish_topics = ["uptime-kuma", "beszel", "scripts"]
}

# The phone apps (Android, iOS) and the publishers (Uptime Kuma, Beszel,
# scripts) talk to ntfy from wherever they are and cannot pass the SSO wall:
# none of them holds a Pangolin session. ACCEPT through local.path_bypasses
# (rules.tf), from any country like every path ACCEPT. Every route below runs
# ntfy's own authorization first: auth-default-access is deny-all, so nothing
# answers without a declared account (Basic, the phone) or token (Bearer, the
# publishers), and each producer token only writes its own topic (role ntfy).
# Read off the ntfy v2.34.0 sources (server/server.go, handleInternal and the
# path regexes above it) and the clients that call them:
#
# - `/`: publishing as JSON, the topic in the body (POST/PUT /, handlePublish
#   then the topic's write check). Uptime Kuma's ntfy provider posts there,
#   always (server/notification-providers/ntfy.js: axios.post(ntfyserverurl)).
#   Exact path: Pangolin's matcher (server/lib/pathMatch.ts) gives `/` no
#   segment, so it matches the root and nothing under it. GET / serves the
#   web app's HTML shell, whose /static/* stays behind the SSO.
# - `/<topic>`, for each of local.ntfy_publish_topics: publishing to one
#   topic (POST/PUT, topicPathRegex): Beszel's shoutrrr (pkg/services/push/
#   ntfy GetAPIURL: /<topic>), curl in the scripts, and the app's own "publish"
#   (ApiService.publish). Exact topic paths, not a `/*`: a bare `*` segment
#   matches every path of the server. A GET there only serves the web app's
#   HTML shell (handleTopic), or `{"unifiedpush":{"version":1}}` with ?up=1.
# - `/*/json`: the subscription stream and the poll (`?poll=1`) that the apps
#   run on a poll_request relayed by ntfy.sh (Android ApiService.poll and
#   subscribe, iOS ApiService.poll). `/*/ws`: the Android WebSocket
#   connection (WsConnection, instant delivery). `/*/auth`: the login check
#   when an account is added to the app (topicUrlAuth, iOS topicAuthUrl).
#   The middle `*` because the Android app joins several topics with commas
#   in one segment (`/a,b/ws`); in Pangolin a bare `*` segment also matches
#   zero or several segments, but ntfy's regexes take exactly one topic list
#   segment and answer 404 otherwise. Each one runs authorizeTopicRead on
#   every topic of the list.
#
# Not opened: the web app and its API (/static/*, /v1/config, /v1/account*,
# /v1/webpush: only used by the browser, under the SSO session), the
# server-side SSE and raw streams (/*/sse, /*/raw: no app nor publisher of
# this homelab uses them), message updates and deletion (/<topic>/<id>...),
# /file/* (attachments are disabled), /v1/health (the target healthcheck,
# hc_path, which Newt runs from inside; the Uptime Kuma monitor probes `/`),
# /metrics (disabled), /_matrix/* (no Matrix
# gateway here), and the admin routes (/v1/users*, /v1/version).
locals {
  ntfy_client_paths = merge(
    {
      "/"       = 2
      "/*/json" = 2
      "/*/ws"   = 2
      "/*/auth" = 2
    },
    { for topic in local.ntfy_publish_topics : "/${topic}" => 2 },
  )
}

# Uptime Kuma's ntfy channel, publishing to the uptime-kuma topic with that
# producer's write-only token. Declared but wired to no monitor yet: Sylvain
# decides (e-mail stays the default channel). To use it on every monitor,
# add `uptimekuma_notification_ntfy.ntfy.id` next to
# `uptimekuma_notification_smtp.email.id` in the `notification_ids` of the
# monitors to switch (websites.tf, external_monitors.tf...), or set
# is_default = true here so that a monitor made by hand in the UI gets it.
#
# The token is the key ntfy_uptime_kuma_token of the root secrets.sops.yaml:
# docker.yml reads it back from this state (output ntfy_uptime_kuma_token)
# and declares it in ntfy, so it is written in one place only.
resource "uptimekuma_notification_ntfy" "ntfy" {
  name = "ntfy"

  server_url            = "https://ntfy.sylvain.cloud"
  topic                 = "uptime-kuma"
  authentication_method = "accessToken"
  access_token          = local.ntfy_uptime_kuma_token
  # 4 (high): a sound and a heads-up on the phone, without the 5 (max)
  # that overrides Do Not Disturb.
  priority = 4

  # Optional+computed: pinned, as on uptimekuma_notification_smtp.email.
  is_active      = true
  is_default     = false
  apply_existing = false
}

output "ntfy_access_token" {
  description = "NTFY - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["ntfy"]
  sensitive   = true
}

output "uptime_backup_ntfy_url" {
  description = "NTFY - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["ntfy"]
  sensitive   = true
}

# Read by docker.yml (role ntfy, producer uptime-kuma).
output "ntfy_uptime_kuma_token" {
  description = "NTFY - Jeton d'accès du producteur uptime-kuma (écriture seule sur son topic)"
  value       = local.ntfy_uptime_kuma_token
  sensitive   = true
}
