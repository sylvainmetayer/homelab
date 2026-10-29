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

# Telegram: the only alert of FolderSync (external_monitors.tf) and of the SSH
# login monitors (ssh_login_monitors.tf), which must arrive at once.
#
# It replaces notification 1, "Supervision Telegram", made by hand, which
# cannot be imported: the UI stored its chat id as a JSON number and provider
# 0.4.0 fails to read it ("cannot unmarshal number into ...telegramChatID of
# type string"), on import as on every refresh. This one is created instead,
# same bot and chat (root secrets.sops.yaml), and the hand-made one is deleted
# in the UI once the monitors point here - after checking that no hand-made
# monitor (the professional ones) still lists it, or that one loses its alert.
#
# Never edit this one in the UI: saving the form may store the chat id as a
# number again, and every refresh of this module would then fail as above.
resource "uptimekuma_notification_telegram" "supervision" {
  name = "Telegram"

  bot_token = local.telegram_bot_token
  chat_id   = local.telegram_chat_id

  # All optional+computed, pinned (see the SMTP notification above).
  is_active      = true
  is_default     = false # e-mail stays the default; Telegram is opt-in
  apply_existing = false

  server_url          = "https://api.telegram.org"
  send_silently       = false
  protect_content     = false
  use_template        = false
  template_parse_mode = "HTML"
}
