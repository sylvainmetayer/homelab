# Resource, target and monitors: local.websites (websites.tf).
locals {
  nextcloud_website = {
    name      = "nextcloud"
    subdomain = null
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "nextcloud"
    backup    = true

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      title       = "Nextcloud"
      group       = "Documents"
      description = "Fichiers synchronisés"
      icon        = "nextcloud"
    }

    # Behind the SSO (the default), clients and share links opened by path:
    # see local.nextcloud_client_paths and local.nextcloud_share_paths below.
    # The healthcheck monitor probes `/` with the access token, which now
    # really is what lets it past the wall (`/` redirects to Nextcloud's
    # /login, which no path rule opens).

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "nextcloud"
      port    = 80
      hc_path = "/login"
    }
  }
}

# Behind the SSO wall since it got these path rules. It used to be sso = false,
# the only private app answering FR and DE with no Pangolin login in the way,
# because two kinds of callers cannot do an SSO redirect: the desktop, Android,
# iOS and DAVx5 clients (WebDAV/OCS with HTTP Basic or a bearer) and the
# visitors of a public share link, who have no account. Both now go through
# local.path_bypasses (rules.tf), from anywhere and without SSO; everything
# else - web UI, login form, admin pages, every app's UI and API not listed
# below - needs a Pangolin session first. Nextcloud's own authentication still
# applies behind every opened path, and the nextcloud Ansible role sets
# token_auth_enforced so that what reaches DAV/OCS without SSO is an app
# password, never the account password (ansible/roles/nextcloud).
#
# Read off Nextcloud 35.0.1 as the linuxserver image serves it (nginx front
# controller with front_controller_active, so a route answers both as `/x` and
# as `/index.php/x`, and the server generates the first form) and off the
# clients that talk to it: desktop (src/libsync, src/gui/wizard), Android (app
# and android-library), iOS (NextcloudKit), DAVx5. Re-read them when a major
# version lands.
#
# 1. Clients, local.nextcloud_client_paths:
#    - /status.php: the first request of every client (server detection,
#      maintenance flag), anonymous JSON.
#    - /index.php/204: Android's connectivity check (ConnectivityServiceImpl.kt).
#      Behind the wall it gets a redirect instead of a 204, the app concludes
#      it sits behind a captive portal and auto-upload pauses without a word.
#    - /remote.php/*: WebDAV (files, chunked uploads, trashbin, versions),
#      CalDAV and CardDAV, with Basic auth (app password) or a bearer.
#    - /ocs/v1.php/*, /ocs/v2.php/*: capabilities, user, shares, notifications,
#      activity, app password conversion and deletion.
#    - Login flow v2, the client half only: the anonymous POST that starts it
#      (exact `/index.php/login/v2`, nothing under it) and the poll, under the
#      URL the server hands back (`/login/v2/poll`) and the one some clients
#      build themselves (`/index.php/login/v2/poll`). The browser half -
#      /login/v2/flow/*, /login/v2/grant, /login/v2/apptoken - stays behind the
#      SSO: the client opens it in the system browser, which goes through
#      Pangolin's login like any visit.
#    - /index.php/core/wipe/*: remote wipe check and acknowledgement, POSTed
#      with the app password and rate-limited (WipeController).
#    - File-list thumbnails: /index.php/core/preview and
#      /index.php/apps/files/api/v1/thumbnail/*, same credentials.
#    - /.well-known/caldav, /.well-known/carddav: DAVx5 and Thunderbird
#      discovery, a 301 to /remote.php/dav/ answered by nginx.
#    Deliberately not opened: avatars (cosmetic in the apps), the Notes and
#    Deck APIs (/index.php/apps/notes/api/*, /index.php/apps/deck/api/*) and
#    notify_push (not installed).
#
# 2. Public share links, local.nextcloud_share_paths: the page `/s/<token>`
#    (random token, optional password and expiry, checked by files_sharing),
#    its downloads and public WebDAV (/public.php/*), its API and previews
#    (files_sharing), the theming CSS and logo, the build (/dist/*), the core
#    and per-app static files, /csrftoken, the files preview service worker and
#    the Text editor's public endpoints for a shared Markdown file. The
#    `/index.php/...` forms sit next to the pretty ones because older links and
#    some calls carry them.
#
#    Two entries are broader than they read:
#    - `/core/*` also reaches core's pretty routes (preview, mimeicon, wipe,
#      reference previews, recommended apps), each behind its controller's own
#      authentication.
#    - `/apps/*/js/*` and its css/img/l10n siblings: Pangolin's `*` spans
#      several segments, so they match any /apps/... path holding a `js`
#      (`css`, `img`, `l10n`) segment anywhere, an app route included.
#    Such a route skips the SSO wall and the country filter, not Nextcloud's
#    authentication. Accepted rather than listing every app's assets by name.
locals {
  nextcloud_client_paths = {
    "/status.php"                              = 4
    "/index.php/204"                           = 4
    "/remote.php/*"                            = 4
    "/ocs/v1.php/*"                            = 4
    "/ocs/v2.php/*"                            = 4
    "/index.php/login/v2"                      = 4
    "/login/v2/poll"                           = 4
    "/index.php/login/v2/poll"                 = 4
    "/index.php/core/wipe/*"                   = 4
    "/index.php/core/preview"                  = 4
    "/index.php/apps/files/api/v1/thumbnail/*" = 4
    "/.well-known/caldav"                      = 4
    "/.well-known/carddav"                     = 4
  }

  nextcloud_share_paths = {
    "/s/*"                                            = 4
    "/index.php/s/*"                                  = 4
    "/public.php/*"                                   = 4
    "/apps/files_sharing/*"                           = 4
    "/index.php/apps/files_sharing/*"                 = 4
    "/apps/theming/*"                                 = 4
    "/index.php/apps/theming/*"                       = 4
    "/dist/*"                                         = 4
    "/core/*"                                         = 4
    "/apps/*/js/*"                                    = 4
    "/apps/*/css/*"                                   = 4
    "/apps/*/img/*"                                   = 4
    "/apps/*/l10n/*"                                  = 4
    "/csrftoken"                                      = 4
    "/index.php/csrftoken"                            = 4
    "/index.php/apps/files/preview-service-worker.js" = 4
    "/apps/text/public/*"                             = 4
  }
}

output "nextcloud_access_token" {
  description = "NEXTCLOUD - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["nextcloud"]
  sensitive   = true
}

output "uptime_backup_nextcloud_url" {
  description = "NEXTCLOUD - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["nextcloud"]
  sensitive   = true
}
