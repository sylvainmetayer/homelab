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
# alerts.
#
# Every monitor of this module alerts on Telegram and ntfy (website_ntfy.tf)
# through this local. E-mail was the channel until 2026-10-29 and is gone:
# ntfy rides on Pangolin (ntfy.sylvain.cloud), Telegram does not, so an outage
# of Pangolin itself still reaches the phone. Only the SSH login monitors
# (ssh_login_monitors.tf) keep Telegram alone.
#
# No channel is the default any more: e-mail was (is_default = true), so a
# monitor made by hand in the UI (the professional ones) may list it, and
# loses its only alert when the apply deletes it. Before that apply, give each
# hand-made monitor Telegram or ntfy in the UI; one made afterwards gets no
# channel unless picked.
# ---------------------------------------------------------------------------
locals {
  alert_notification_ids = [
    uptimekuma_notification_telegram.supervision.id,
    uptimekuma_notification_ntfy.ntfy.id,
  ]
}

# Telegram: one of the two alerts of every monitor (alert_notification_ids
# above), and the only one of the SSH login monitors (ssh_login_monitors.tf),
# which must arrive at once.
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

  # `is_active`, `is_default` and `apply_existing` are optional+computed.
  # Leaving them out means "whatever the API decides", which is exactly how
  # the health-check probes ended up silently unconfigured - so every one is
  # pinned here on purpose.
  is_active      = true
  is_default     = false # monitors are wired explicitly, none by default
  apply_existing = false

  server_url          = "https://api.telegram.org"
  send_silently       = false
  protect_content     = false
  use_template        = false
  template_parse_mode = "HTML"
}
