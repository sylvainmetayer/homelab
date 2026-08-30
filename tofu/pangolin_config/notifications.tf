# ---------------------------------------------------------------------------
# Downtime alerting.
#
# Until this existed, Uptime Kuma watched every app but told nobody: gramps and
# scanopy served 503 for hours with no alert, and the outage was only found by
# reading the Pangolin API by hand. Monitoring without a notification channel
# is just a dashboard you have to remember to open.
#
# Uptime Kuma sends on both edges by default - once when a monitor goes DOWN,
# once when it comes back UP - so no extra configuration is needed for recovery
# mail.
# ---------------------------------------------------------------------------
resource "uptimekuma_notification_smtp" "email" {
  name = "Email"

  host     = "mail.infomaniak.com"
  port     = 465
  secure   = true # implicit TLS on 465, same as Pangolin's own SMTP config
  username = local.smtp_user
  password = local.smtp_pass

  from = local.smtp_user
  to   = local.alert_email

  # `is_active`, `is_default`, `html_body`, `ignore_tls_error` and
  # `apply_existing` are all optional+computed. Leaving them out means
  # "whatever the API decides", which is exactly how the health-check probes
  # ended up silently unconfigured - so they are pinned here on purpose.
  is_active  = true
  is_default = true # a monitor added by hand in the UI gets it too

  html_body        = true
  ignore_tls_error = false

  # Monitors are wired explicitly below, so this must not also bulk-attach.
  apply_existing = false
}
