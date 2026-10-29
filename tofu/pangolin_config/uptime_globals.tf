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
  # a blip shorter than a minute never pages (the external monitors used to
  # page on the first failure, max_retries 0), and a real outage pages within
  # interval + retry_interval, six minutes at worst (plus each attempt's
  # timeout when the app hangs rather than refuses). resend_interval 0: one
  # alert per outage, no reminder.
  http_probe = {
    interval        = 60 * 5
    max_retries     = 1
    retry_interval  = 60
    resend_interval = 0
  }
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

# TODO
# https://registry.terraform.io/providers/breml/uptimekuma/latest/docs/resources/monitor_dns
