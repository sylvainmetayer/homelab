# ---------------------------------------------------------------------------
# Monitors for things this repository does not host.
#
# They predate the configuration and lived only in the Uptime Kuma UI. Declared
# here after the August 2026 audit so the instance has no unmanaged corners
# left, not because this repo deploys any of them.
#
# Everything below mirrors the live monitors, `tofu import` included - Ref and
# Planning (vitrine), added afterwards, being the exceptions. Each alerts on
# Telegram and ntfy like the rest of the module (local.alert_notification_ids,
# notifications.tf; until 2026-10-29 none paged anybody but FolderSync). Their
# cadence and retries are the module's (local.http_probe, uptime_globals.tf) since
# 2026-10-29: one probe every five minutes, a DOWN only after a retry, where
# the imported `max_retries = 0` paged on a single failed probe.
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

  interval        = local.http_probe.interval
  timeout         = 48
  max_retries     = local.http_probe.max_retries
  retry_interval  = local.http_probe.retry_interval
  resend_interval = local.http_probe.resend_interval
  active          = true
  method          = "GET"

  domain_expiry_notification = true
  expiry_notification        = false
  notification_ids           = local.alert_notification_ids
  tags                       = [local.tofu_tag]
}

# r.sylvain.dev, the 1y short-URL site: moved from Netlify to Cloudflare Pages
# (tofu/1y), so filed under the Cloudflare folder.
resource "uptimekuma_monitor_http" "redirect" {
  name   = "Redirect"
  parent = uptimekuma_monitor_group.cloudflare.id
  url    = "https://r.sylvain.dev"

  interval        = local.http_probe.interval
  timeout         = 48
  max_retries     = local.http_probe.max_retries
  retry_interval  = local.http_probe.retry_interval
  resend_interval = local.http_probe.resend_interval
  active          = true
  method          = "GET"

  domain_expiry_notification = true
  expiry_notification        = true
  notification_ids           = local.alert_notification_ids
  tags                       = [local.tofu_tag]
}

# Servi par Cloudflare Pages sur www depuis la migration (tofu/site).
resource "uptimekuma_monitor_http" "blog" {
  name   = "Blog"
  parent = uptimekuma_monitor_group.cloudflare.id
  url    = "https://www.sylvain.dev"

  interval        = local.http_probe.interval
  timeout         = 48
  max_retries     = local.http_probe.max_retries
  retry_interval  = local.http_probe.retry_interval
  resend_interval = local.http_probe.resend_interval
  active          = true
  method          = "GET"

  domain_expiry_notification = true
  expiry_notification        = true
  notification_ids           = local.alert_notification_ids
  tags                       = [local.tofu_tag]
}

# L'apex pointe vers Pangolin, dont Traefik redirige en 301 vers www
# (pangolin_domain_redirects) : le moniteur suit la redirection.
resource "uptimekuma_monitor_http" "blog_apex" {
  name   = "Blog (apex)"
  parent = uptimekuma_monitor_group.cloudflare.id
  url    = "https://sylvain.dev"

  interval        = local.http_probe.interval
  timeout         = 48
  max_retries     = local.http_probe.max_retries
  retry_interval  = local.http_probe.retry_interval
  resend_interval = local.http_probe.resend_interval
  active          = true
  method          = "GET"

  domain_expiry_notification = true
  expiry_notification        = true
  notification_ids           = local.alert_notification_ids
  tags                       = [local.tofu_tag]
}

resource "uptimekuma_monitor_group" "cloudflare" {
  name   = "Cloudflare"
  active = true
  tags   = [local.tofu_tag]
}

# ref.sylvain.dev, the referral site (tofu/ref, Cloudflare Pages). Not a mirror
# of a live monitor: it had none. Same shape as Redirect and Blog.
resource "uptimekuma_monitor_http" "ref" {
  name   = "Ref"
  parent = uptimekuma_monitor_group.cloudflare.id
  url    = "https://ref.sylvain.dev"

  interval        = local.http_probe.interval
  timeout         = 48
  max_retries     = local.http_probe.max_retries
  retry_interval  = local.http_probe.retry_interval
  resend_interval = local.http_probe.resend_interval
  active          = true
  method          = "GET"

  domain_expiry_notification = true
  expiry_notification        = true
  notification_ids           = local.alert_notification_ids
  tags                       = [local.tofu_tag]
}

# planning.sylvain.dev, the planning-equipes showcase (tofu/planning,
# Cloudflare Pages). Same shape as Ref. Apply tofu/planning (and run the first
# deployment) before this one, or it pages DOWN until the site answers.
resource "uptimekuma_monitor_http" "planning_site" {
  name   = "Planning (vitrine)"
  parent = uptimekuma_monitor_group.cloudflare.id
  url    = "https://planning.sylvain.dev"

  interval        = local.http_probe.interval
  timeout         = 48
  max_retries     = local.http_probe.max_retries
  retry_interval  = local.http_probe.retry_interval
  resend_interval = local.http_probe.resend_interval
  active          = true
  method          = "GET"

  domain_expiry_notification = true
  expiry_notification        = true
  notification_ids           = local.alert_notification_ids
  tags                       = [local.tofu_tag]
}

resource "uptimekuma_monitor_http" "agent_ready_cloudflare" {
  name   = "Agent Ready"
  parent = uptimekuma_monitor_group.cloudflare.id
  url    = "https://agent-ready.pages.dev/"

  interval        = local.http_probe.interval
  timeout         = 48
  max_retries     = local.http_probe.max_retries
  retry_interval  = local.http_probe.retry_interval
  resend_interval = local.http_probe.resend_interval
  active          = true
  method          = "GET"

  domain_expiry_notification = true
  expiry_notification        = true
  notification_ids           = local.alert_notification_ids
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

  interval        = local.http_probe.interval
  timeout         = 48
  max_retries     = local.http_probe.max_retries
  retry_interval  = local.http_probe.retry_interval
  resend_interval = local.http_probe.resend_interval
  active          = true
  method          = "GET"

  domain_expiry_notification = true
  expiry_notification        = true
  notification_ids           = local.alert_notification_ids
  tags                       = [local.tofu_tag]
}

resource "uptimekuma_monitor_http" "simplelogin" {
  name   = "SimpleLogin"
  parent = uptimekuma_monitor_group.third_parties.id
  url    = "https://app.simplelogin.io/"

  interval        = local.http_probe.interval
  timeout         = 48
  max_retries     = local.http_probe.max_retries
  retry_interval  = local.http_probe.retry_interval
  resend_interval = local.http_probe.resend_interval
  active          = true
  method          = "GET"

  domain_expiry_notification = false
  expiry_notification        = true
  notification_ids           = local.alert_notification_ids
  tags                       = [local.tofu_tag]
}

# --- Unfiled ---------------------------------------------------------------

resource "uptimekuma_monitor_http" "ustalence_tt" {
  name = "US Talence Tennis de Table"
  url  = "https://ustalencett.fr"

  interval        = local.http_probe.interval
  timeout         = 48
  max_retries     = local.http_probe.max_retries
  retry_interval  = local.http_probe.retry_interval
  resend_interval = local.http_probe.resend_interval
  active          = true
  method          = "GET"

  domain_expiry_notification = true
  expiry_notification        = true
  notification_ids           = local.alert_notification_ids
  tags                       = [local.tofu_tag]
}

# Pushed by something outside this repository (Ansible never touches this
# token), so the heartbeat source stays as it is; only the definition lives
# here.
#
# Alerts on Telegram and ntfy, like every monitor of this module.
resource "uptimekuma_monitor_push" "foldersync" {
  name   = "FolderSync"
  parent = uptimekuma_monitor_group.backups.id

  interval        = 86410
  retry_interval  = 86410
  resend_interval = 0
  active          = true

  notification_ids = local.alert_notification_ids
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
