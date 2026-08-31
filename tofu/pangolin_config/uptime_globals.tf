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
