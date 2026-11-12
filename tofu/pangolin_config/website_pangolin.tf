# The Pangolin dashboard itself. Every resource healthcheck goes through
# Pangolin, so they all turn red together when it is down - but nothing watched
# the dashboard, which can fail on its own (Next.js on 3002, behind its own
# Traefik routers in the pangolin role's dynamic config) while the proxied
# sites still answer.
#
# The hostname is pangolin_dashboard_url in ansible/host_vars/pangolin (hall.,
# since the rename), pinned by a test. A plain status monitor rather than the
# inverted keyword: the dashboard is not a pangolin_resource, so it has no
# maintenance page and a dead dashboard does fail (see maintenance.tf). `/`
# redirects to the login page, which Uptime Kuma follows.
resource "uptimekuma_monitor_http" "pangolin_dashboard" {
  name = "Dashboard Pangolin"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  url             = "https://${local.pangolin_dashboard_host}"
  interval        = local.http_probe.interval
  timeout         = 30
  max_retries     = local.http_probe.max_retries
  retry_interval  = local.http_probe.retry_interval
  resend_interval = local.http_probe.resend_interval
  active          = true
  method          = "GET"

  expiry_notification = true
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = local.alert_notification_ids
}

# L'ancien nom du tableau de bord, sur l'API seule : c'est par lui que les Newt
# et OLM déjà installés joignent Pangolin (newt_endpoint, runners CI), alors
# que ses pages renvoient (302) vers le nom courant. Un nom ou un routeur
# retiré par mégarde couperait les tunnels sans que le moniteur du tableau de
# bord rougisse. À retirer avec pangolin_dashboard_legacy_url (rôle pangolin).
resource "uptimekuma_monitor_http" "pangolin_dashboard_legacy_api" {
  name = "API Pangolin (ancien nom)"

  parent = uptimekuma_monitor_group.self_hosted.id

  url             = "https://${local.pangolin_dashboard_legacy_host}/api/v1/"
  interval        = local.http_probe.interval
  timeout         = 30
  max_retries     = local.http_probe.max_retries
  retry_interval  = local.http_probe.retry_interval
  resend_interval = local.http_probe.resend_interval
  active          = true
  method          = "GET"

  # Même certificat joker (*.sylvain.cloud) que le moniteur du tableau de bord,
  # qui alerte déjà sur son expiration : pas une seconde alerte pour le même.
  expiry_notification = false
  tags                = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = local.alert_notification_ids
}

resource "uptimekuma_monitor_push" "backup_pangolin" {
  name = "Backup Pangolin"

  # Grouped under the Backup folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.backups.id

  interval = local.backup_push_interval

  # A missed window or a pushed `down` pages at once. See uptime_globals.tf.
  max_retries    = local.push_down_max_retries
  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.backup.id }]

  notification_ids = local.alert_notification_ids
}

output "uptime_backup_pangolin_url" {
  description = "PANGOLIN - URL pour envoyer les heartbeats push"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.backup_pangolin.push_token}"
  sensitive   = true
}

# Mise à jour hebdomadaire de GeoLite2 sur Pangolin (geoipupdate.timer, rôle
# pangolin) : tout le géofiltre en dépend. Le timer passe le mercredi ; un
# jour de marge avant l'alerte.
resource "uptimekuma_monitor_push" "cron_geoip" {
  name = "GeoIP Pangolin"

  # Not a backup: grouped with the healthchecks. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval = 60 * 60 * 24 * 8

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = local.alert_notification_ids
}

output "uptime_cron_geoip_url" {
  description = "PANGOLIN - URL push de la mise à jour GeoLite2 (geoipupdate)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_geoip.push_token}"
  sensitive   = true
}
