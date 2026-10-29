# Échéances de rotation des secrets SOPS, chaque lundi
# (.github/workflows/secrets-rotation.yaml, inventaire secrets-rotation.yaml) :
# « up » si aucun secret n'est dû dans les 30 jours, « down » avec les noms
# des clés dues ou en retard, ou si l'inventaire est invalide. Huit jours : un
# run hebdomadaire et un jour de marge pour un run en retard ou relancé.
resource "uptimekuma_monitor_push" "secrets_rotation" {
  name = "Rotation des secrets"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval = 60 * 60 * 24 * 8

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag]

  notification_ids = local.alert_notification_ids
}

# Lu par tofu/github (secret SECRETS_ROTATION_PUSH_URL de l'environnement
# secrets-rotation).
output "uptime_secrets_rotation_url" {
  description = "URL push du contrôle hebdomadaire des échéances de rotation des secrets"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.secrets_rotation.push_token}"
  sensitive   = true
}
