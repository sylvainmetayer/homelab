# Accès de secours sans Pangolin (rôle wireguard_rescue, LXC newt, lxc.yml ;
# ADR 0015) : le LXC vérifie chaque matin son interface WireGuard, son port,
# ses règles nftables et le forwarding (wireguard-rescue-check.timer), et
# pousse up, ou down avec la raison. Le port UDP redirigé par la Bbox, lui,
# ne se vérifie pas d'ici (runbook acces-de-secours.md). Deux jours et une
# heure : une journée manquée passe, pas deux. wireguard_rescue_enabled: false
# arrête les push : passer active à false ici en même temps.
resource "uptimekuma_monitor_push" "cron_wireguard_rescue" {
  name = "Accès de secours"

  # Not a backup: grouped with the healthchecks. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval = 60 * 60 * 49

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

output "uptime_cron_wireguard_rescue_url" {
  description = "LXC newt - URL push de la vérification de l'accès de secours WireGuard (wireguard_rescue)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_wireguard_rescue.push_token}"
  sensitive   = true
}
