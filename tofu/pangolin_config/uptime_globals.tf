resource "uptimekuma_tag" "backup" {
  name  = "backup"
  color = "#0066cc"
}

resource "uptimekuma_tag" "self_hosted" {
  name  = "self_hosted"
  color = "#00ffe1"
}

resource "uptimekuma_monitor_group" "backups" {
  name   = "Backup"
  active = true
}

resource "uptimekuma_monitor_group" "self_hosted" {
  name   = "Self-hosted"
  active = true
}

# TODO
# https://registry.terraform.io/providers/breml/uptimekuma/latest/docs/resources/monitor_dns
