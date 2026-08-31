# ---------------------------------------------------------------------------
# Monitors for things this repository does not host.
#
# They predate the configuration and lived only in the Uptime Kuma UI. Declared
# here after the August 2026 audit so the instance has no unmanaged corners
# left, not because this repo deploys any of them.
#
# Everything below mirrors the live monitors, `tofu import` included. Two live
# properties are mirrored rather than corrected, because fixing them is an
# alerting change and not part of bringing the definitions into code:
#
#   - none of these monitors has a notification attached, so they page nobody;
#     FolderSync is the single exception (Telegram, see below)
#   - `max_retries = 0` means a single failed probe is a DOWN, with no retry
#
# The professional groups further down are folders only. Their children are
# client URLs that have no place in this repository and stay defined by hand in
# Uptime Kuma - importing the folders is what lets the group tree be managed
# without publishing what is inside it.
# ---------------------------------------------------------------------------

# --- Externally hosted -----------------------------------------------------

resource "uptimekuma_monitor_group" "pikapods" {
  name   = "PikaPods"
  active = true
  tags   = [local.tofu_tag]
}

resource "uptimekuma_monitor_http" "actualbudget" {
  name   = "ActualBudget"
  parent = uptimekuma_monitor_group.pikapods.id
  url    = "https://budget.sylvain.cloud"

  interval        = 60
  timeout         = 48
  max_retries     = 0
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  domain_expiry_notification = true
  expiry_notification        = false
  tags                       = [local.tofu_tag]
}

resource "uptimekuma_monitor_group" "netlify" {
  name   = "Netlify"
  active = true
  tags   = [local.tofu_tag]
}

resource "uptimekuma_monitor_http" "alias_gandi" {
  name   = "Alias Gandi"
  parent = uptimekuma_monitor_group.netlify.id
  url    = "https://alias-gandi-angular.netlify.app/"

  interval        = 60
  timeout         = 48
  max_retries     = 0
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  domain_expiry_notification = true
  expiry_notification        = true
  tags                       = [local.tofu_tag]
}

# Same name as the Cloudflare one below - they are two deployments of the same
# site, told apart by their folder.
resource "uptimekuma_monitor_http" "agent_ready_netlify" {
  name   = "Agent Ready"
  parent = uptimekuma_monitor_group.netlify.id
  url    = "https://agent-ready.netlify.app/"

  interval        = 60
  timeout         = 48
  max_retries     = 0
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  domain_expiry_notification = true
  expiry_notification        = true
  tags                       = [local.tofu_tag]
}

resource "uptimekuma_monitor_http" "redirect" {
  name   = "Redirect"
  parent = uptimekuma_monitor_group.netlify.id
  url    = "https://r.sylvain.dev"

  interval        = 60
  timeout         = 48
  max_retries     = 0
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  domain_expiry_notification = true
  expiry_notification        = true
  tags                       = [local.tofu_tag]
}

resource "uptimekuma_monitor_http" "blog" {
  name   = "Blog"
  parent = uptimekuma_monitor_group.netlify.id
  url    = "https://sylvain.dev"

  interval        = 60
  timeout         = 48
  max_retries     = 0
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  domain_expiry_notification = true
  expiry_notification        = true
  tags                       = [local.tofu_tag]
}

resource "uptimekuma_monitor_group" "cloudflare" {
  name   = "Cloudflare"
  active = true
  tags   = [local.tofu_tag]
}

resource "uptimekuma_monitor_http" "agent_ready_cloudflare" {
  name   = "Agent Ready"
  parent = uptimekuma_monitor_group.cloudflare.id
  url    = "https://agent-ready.pages.dev/"

  interval        = 60
  timeout         = 48
  max_retries     = 0
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  domain_expiry_notification = true
  expiry_notification        = true
  tags                       = [local.tofu_tag]
}

# --- Third-party SaaS ------------------------------------------------------

resource "uptimekuma_monitor_group" "third_parties" {
  name   = "Third Parties"
  active = true
  tags   = [local.tofu_tag]
}

resource "uptimekuma_monitor_http" "kdrive" {
  name   = "kDrive"
  parent = uptimekuma_monitor_group.third_parties.id
  url    = "https://kdrive.infomaniak.com/app/drive"

  interval        = 60
  timeout         = 48
  max_retries     = 0
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  domain_expiry_notification = true
  expiry_notification        = true
  tags                       = [local.tofu_tag]
}

resource "uptimekuma_monitor_http" "simplelogin" {
  name   = "SimpleLogin"
  parent = uptimekuma_monitor_group.third_parties.id
  url    = "https://app.simplelogin.io/"

  interval        = 60
  timeout         = 48
  max_retries     = 0
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  domain_expiry_notification = false
  expiry_notification        = true
  tags                       = [local.tofu_tag]
}

# --- Unfiled ---------------------------------------------------------------

resource "uptimekuma_monitor_http" "ustalence_tt" {
  name = "US Talence Tennis de Table"
  url  = "https://ustalencett.fr"

  interval        = 60
  timeout         = 48
  max_retries     = 0
  retry_interval  = 60
  resend_interval = 0
  active          = true
  method          = "GET"

  domain_expiry_notification = true
  expiry_notification        = true
  tags                       = [local.tofu_tag]
}

# Pushed by something outside this repository (Ansible never touches this
# token), so the heartbeat source stays as it is; only the definition moves
# here. Reparented from the legacy "Backups" folder to the managed one, which
# leaves that folder empty and deletable.
#
# Notification 1 is "Supervision Telegram", created by hand: its bot token is
# not in sops, so the notification itself cannot be declared and the id is
# referenced raw. Changing it would silently drop this monitor's only alert.
resource "uptimekuma_monitor_push" "foldersync" {
  name   = "FolderSync"
  parent = uptimekuma_monitor_group.backups.id

  interval        = 86410
  retry_interval  = 86410
  resend_interval = 0
  active          = true

  notification_ids = [1]
  tags             = [local.tofu_tag]
}

# --- Professional: folders only, children stay manual ----------------------

resource "uptimekuma_monitor_group" "onepoint" {
  name   = "onepoint"
  active = true
  tags   = [local.tofu_tag]
}

resource "uptimekuma_monitor_group" "oru" {
  name   = "ORU"
  parent = uptimekuma_monitor_group.onepoint.id
  active = true
  tags   = [local.tofu_tag]
}

resource "uptimekuma_monitor_group" "pole_edition" {
  name   = "Pôle Édition"
  parent = uptimekuma_monitor_group.onepoint.id
  active = true
  tags   = [local.tofu_tag]
}

resource "uptimekuma_monitor_group" "talks" {
  name   = "Talks"
  parent = uptimekuma_monitor_group.onepoint.id
  active = true
  tags   = [local.tofu_tag]
}
