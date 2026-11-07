# Santé des applis du NAS (Jellyfin, MediaManager), servies par le Traefik du
# NAS (rôle nas_proxy) sur le LAN et par le client Pangolin seulement : un
# moniteur HTTP de cet Uptime Kuma (PikaPods) ne les joint pas. Le NAS les
# interroge lui-même toutes les 5 minutes (nas-health-check.timer, rôle
# nas_proxy, nas.yml), par son Traefik (TLS et nom compris), et pousse UN
# résultat : up si toutes répondent, sinon down avec la raison de chacune en
# échec (un seul moniteur : une panne du NAS ne sonne qu'une fois). La sortie
# uptime_health_nas_url est lue par nas.yml. Dix minutes, deux
# périodes du timer : une fenêtre d'une seule période ferait la course avec
# chaque push. Un down poussé passe d'abord en PENDING (max_retries) : il faut
# deux vérifications en échec de suite (~5 min) pour alerter ; un NAS muet
# alerte au bout de 15 minutes (fenêtre, puis un essai). Telegram et ntfy.
#
# MediaManager est à l'essai : le retirer ne touche plus ce fichier, seulement
# son entrée de nas_proxy_health_checks (ansible/roles/mediamanager/README.md).
resource "uptimekuma_monitor_push" "health_nas" {
  name        = "Healthcheck NAS"
  description = "Applis du NAS (Jellyfin, MediaManager), par son Traefik (nas-health-check.timer, rôle nas_proxy)."

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval        = 60 * 10
  retry_interval  = 60 * 5
  max_retries     = 1
  resend_interval = 0
  upside_down     = false
  active          = true
  tags            = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = local.alert_notification_ids
}

output "uptime_health_nas_url" {
  description = "NAS - URL push de la santé des applis (nas_proxy)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.health_nas.push_token}"
  sensitive   = true
}
