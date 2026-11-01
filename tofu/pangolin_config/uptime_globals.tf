resource "uptimekuma_tag" "backup" {
  name  = "backup"
  color = "#0066cc"
}

resource "uptimekuma_tag" "self_hosted" {
  name  = "self_hosted"
  color = "#00ffe1"
}

# Ownership marker. Every monitor and folder this configuration creates carries
# it, so "what is in the code" is answerable from the Uptime Kuma UI alone -
# which is what the 45 undeclared monitors found in the August 2026 audit cost a
# socket.io dump to establish.
resource "uptimekuma_tag" "managed_by" {
  name  = "managed-by"
  color = "#7b42bc"
}

# No local of pins for the monitors, unlike local.resource_pins
# (resource_defaults.tf): in breml/uptimekuma 0.4.0, every optional+computed
# attribute of uptimekuma_monitor_push, _group, _http and _http_keyword
# (upside_down, active, max_retries, accepted_status_codes, ignore_tls...)
# carries a static provider default (resource_monitor_base.go,
# resource_monitor_http_base.go) and is read back from the server on refresh.
# Left out, it is pinned to that default: a box ticked in the UI (upside_down
# on a push monitor, green with no push) shows in the next plan as an update
# back. Re-check on a provider upgrade: an attribute that loses its default
# becomes "(known after apply)", the silent shape pangolin_resource had.
locals {
  # Spelled out once: a tag with a value is a per-monitor association, not a
  # property of the tag itself, so it has to be repeated on every resource.
  tofu_tag = { tag_id : uptimekuma_tag.managed_by.id, value : "tofu" }

  # Cadence of every HTTP monitor (app healthchecks, the Pangolin dashboard,
  # the external sites); push monitors keep their own. Every five minutes
  # since 2026-10-29: at one probe a minute, the healthchecks were 990k of
  # the 1.52M lines of Pangolin's request log (each goes through an access
  # token) and weighed on its SQLite, where "database is locked" was seen.
  #
  # A failed probe turns the monitor PENDING and retries once a minute later;
  # only the second failure in a row is a DOWN and pages (Telegram, ntfy). So
  # a blip shorter than a minute never pages, and a real outage pages within
  # interval + retry_interval, six minutes at worst (plus each attempt's
  # timeout when the app hangs rather than refuses). resend_interval 0: one
  # alert per outage, no reminder.
  http_probe = {
    interval        = 60 * 5
    max_retries     = 1
    retry_interval  = 60
    resend_interval = 0
  }

  # Window of every backup push monitor (uptimekuma_monitor_push.backup,
  # backup_pangolin, backup_jellyfin). The borgmatic timers fire at a fixed
  # local time (01:00, 02:30 on the NAS, Europe/Paris), and the push comes at
  # the end of the run: the night the clocks go back, two runs are 25 h
  # apart, and a run slower than the one before pushes later still. At
  # exactly 24 h, both paged a backup that did run. 25 h absorbs the hour and
  # still pages the morning after a missed night. Uptime Kuma caps a push
  # monitor at 24 days, far above.
  backup_push_interval = 60 * 60 * 25
}

resource "uptimekuma_monitor_group" "backups" {
  name   = "Backup"
  active = true
  tags   = [local.tofu_tag]
}

resource "uptimekuma_monitor_group" "self_hosted" {
  name   = "Self-hosted"
  active = true
  tags   = [local.tofu_tag]
}
