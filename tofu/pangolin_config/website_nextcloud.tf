resource "pangolin_resource" "nextcloud" {
  name        = "nextcloud"
  subdomain   = null
  domain_id   = local.domain_ids["sylvain.cloud"]
  protocol    = "tcp"
  sso         = true
  apply_rules = true

  # Optional+computed: pinned so a plan can disagree with the API. See
  # resource_defaults.tf.
  mode                    = local.resource_pins.mode
  ssl                     = local.resource_pins.ssl
  enabled                 = local.resource_pins.enabled
  block_access            = local.resource_pins.block_access
  email_whitelist_enabled = local.resource_pins.email_whitelist_enabled
  sticky_session          = local.resource_pins.sticky_session

  # Maintenance screen served automatically while no target is healthy.
  # See maintenance.tf.
  maintenance_mode_enabled = local.maintenance.enabled
  maintenance_mode_type    = local.maintenance.type
  maintenance_title        = local.maintenance.title
  maintenance_message      = local.maintenance.message
}

resource "pangolin_resource_role" "nextcloud" {
  resource_id = pangolin_resource.nextcloud.id
  role_id     = pangolin_role.apps["nextcloud"].id
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
#    - Thumbnails: /index.php/core/preview (and its .png form, some
#      NextcloudKit calls), /index.php/apps/files/api/v1/thumbnail/*, and the
#      trashbin and versions previews, same credentials.
#    - /.well-known/caldav, /.well-known/carddav: DAVx5 and Thunderbird
#      discovery, a 301 to /remote.php/dav/ answered by nginx.
#    Deliberately not opened: avatars (cosmetic in the apps), the Notes and
#    Deck APIs (/index.php/apps/notes/api/*, /index.php/apps/deck/api/*) and
#    notify_push (not installed).
#    What OCS carries, though, is all of OCS: with an ADMIN app password, the
#    provisioning API (/ocs/v2.php/cloud/users, groups, apps) answers from
#    anywhere without SSO too. The clients need /ocs/v2.php/cloud/user and
#    neighbours, and Pangolin cannot tell them apart safely; keep admin
#    accounts' app passwords to the devices that need them.
#
# 2. Public share links, local.nextcloud_share_paths: the page `/s/<token>`
#    (random token, optional password and expiry, checked by files_sharing),
#    its downloads and public WebDAV (/public.php/*), its API and previews
#    (files_sharing), the theming CSS and logo, the build (/dist/*), the core
#    static directories, the per-app static files (shipped apps under /apps,
#    store apps under /custom_apps), /csrftoken, the files preview service
#    worker, the PDF viewer page a shared PDF opens in an iframe, and the Text
#    editor's public endpoints for a shared Markdown file. The
#    `/index.php/...` forms sit next to the pretty ones because older links and
#    some calls carry them.
#
#    /core is opened directory by directory, never as `/core/*`: that would
#    also reach /core/ajax/update.php, the web upgrader, which runs without a
#    login while an upgrade is pending (and /csrftoken, open, hands out the
#    token it checks). A test forbids it.
#
#    Public links of other apps (Calendar /apps/calendar/p/*, appointments,
#    Forms, Talk, Deck, Polls) are not opened: they land on the Pangolin login.
#    Open the app's public prefix here the day such a link is handed out.
#
#    One family of entries is broader than it reads:
#    - `/apps/*/js/*` and its css/img/l10n siblings, and the same under
#      /custom_apps: Pangolin's `*` spans several segments, so they match any
#      /apps/... path holding a `js` (`css`, `img`, `l10n`) segment anywhere,
#      an app route included.
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
    "/index.php/core/preview.png"              = 4
    "/index.php/apps/files_trashbin/preview"   = 4
    "/index.php/apps/files_versions/preview"   = 4
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
    "/core/css/*"                                     = 4
    "/core/fonts/*"                                   = 4
    "/core/img/*"                                     = 4
    "/core/js/*"                                      = 4
    "/core/l10n/*"                                    = 4
    "/core/vendor/*"                                  = 4
    "/apps/*/js/*"                                    = 4
    "/apps/*/css/*"                                   = 4
    "/apps/*/img/*"                                   = 4
    "/apps/*/l10n/*"                                  = 4
    "/custom_apps/*/js/*"                             = 4
    "/custom_apps/*/css/*"                            = 4
    "/custom_apps/*/img/*"                            = 4
    "/custom_apps/*/l10n/*"                           = 4
    "/apps/files_pdfviewer/*"                         = 4
    "/index.php/apps/files_pdfviewer/*"               = 4
    "/csrftoken"                                      = 4
    "/index.php/csrftoken"                            = 4
    "/index.php/apps/files/preview-service-worker.js" = 4
    "/apps/text/public/*"                             = 4
  }
}

resource "pangolin_target" "nextcloud" {
  resource_id = pangolin_resource.nextcloud.id
  site_id     = pangolin_site.proxmox_docker.id
  ip          = "nextcloud"
  port        = 80
  method      = "http"

  hc_enabled             = true
  hc_scheme              = "http"
  hc_mode                = "http"
  hc_port                = 80
  hc_hostname            = "nextcloud"
  hc_path                = "/login"
  hc_method              = "GET"
  hc_status              = 200
  hc_interval            = 30
  hc_unhealthy_interval  = 10
  hc_timeout             = 5
  hc_healthy_threshold   = 2
  hc_unhealthy_threshold = 3
}

resource "pangolin_resource_access_token" "nextcloud" {
  resource_id = pangolin_resource.nextcloud.id
  title       = "Healthcheck ${pangolin_resource.nextcloud.name}"
}

output "nextcloud_access_token" {
  description = "NEXTCLOUD - Token d'accès pour les healthchecks"
  value = jsonencode({
    id    = pangolin_resource_access_token.nextcloud.id,
    token = pangolin_resource_access_token.nextcloud.token
  })
  sensitive = true
}

resource "uptimekuma_monitor_http_keyword" "nextcloud" {
  name = "Healthcheck ${pangolin_resource.nextcloud.name}"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent          = uptimekuma_monitor_group.self_hosted.id
  url             = "https://${pangolin_resource.nextcloud.full_domain}"
  interval        = 60
  timeout         = 30
  max_retries     = 2
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  # Inverted keyword on the maintenance title. See maintenance.tf.
  #
  # Kept on `/` with the access token, like every SSO app. The token was inert
  # while the resource had no SSO; it is now what lets the probe past the
  # wall (`/` redirects to Nextcloud's /login, which no path rule opens). The
  # open /status.php would need no token but tells nothing more: the
  # maintenance page answers on every path of the host. Same blind spot as the
  # other SSO apps: a revoked token shows Pangolin's login page, which holds
  # no maintenance title either.
  keyword        = local.maintenance.title
  invert_keyword = true
  headers = jsonencode({
    "P-Access-Token-Id" = tostring(pangolin_resource_access_token.nextcloud.id),
    "P-Access-Token"    = pangolin_resource_access_token.nextcloud.token
  })
  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

resource "uptimekuma_monitor_push" "backup_nextcloud" {
  name = "Backup ${pangolin_resource.nextcloud.name}"

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  interval = 60 * 60 * 24

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

output "uptime_backup_nextcloud_url" {
  description = "NEXTCLOUD - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_nextcloud.push_token}"
  sensitive   = true
}
