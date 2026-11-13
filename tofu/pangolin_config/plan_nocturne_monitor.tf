# Plan de dérive nocturne de ce module (.github/workflows/plan-pangolin-config.yaml,
# ADR 0035) : le job `notify` pousse « up » quand le plan a tourné (vide ou non :
# un plan non vide alerte sur ntfy), « down » avec la raison quand il n'a pas
# abouti (tunnel, init, API, délai). Deux jours et une heure, comme les contrôles
# nocturnes du NAS : une nuit manquée passe, pas deux ; sans push, le workflow
# est désactivé (60 jours sans activité) ou l'URL révoquée.
resource "uptimekuma_monitor_push" "plan_nocturne" {
  name = "Plan nocturne pangolin_config"

  # Grouped under the Self-hosted folder. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval = 60 * 60 * 49

  # The job pushes `down` with its reason: page at once. See uptime_globals.tf.
  max_retries    = local.push_down_max_retries
  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = local.alert_notification_ids
}

# Lu par tofu/github (secret DRIFT_PLAN_PUSH_URL de l'environnement tofu-drift).
output "uptime_plan_nocturne_url" {
  description = "URL push du plan nocturne de tofu/pangolin_config"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.plan_nocturne.push_token}"
  sensitive   = true
}
