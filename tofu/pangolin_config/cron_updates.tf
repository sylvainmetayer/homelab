# Vérificateur des mises à jour apt en attente (rôle update_notify), un par
# hôte Debian : Proxmox VE (pve.yml), la VM docker (docker.yml), le Pi
# (pi.yml), flip (flip.yml) et Pangolin (pangolin.yaml). Il publie sur ntfy
# (topic scripts) quand quelque chose attend et pousse ici à chaque passage
# hebdomadaire : up avec un résumé, down si apt-get ou ntfy échouent. Sans
# battement (timer arrêté, hôte éteint), le moniteur passe au rouge : un
# vérificateur mort se voit, alors que son silence sur ntfy passerait pour
# « rien à signaler ».
#
# Clé = l'hôte dans la sortie lue par son playbook
# (uptime_cron_<clé>_updates_url), valeur = son nom dans Uptime Kuma.
#
# Quinze jours : un passage manqué passe, pas deux. Sous le plafond de 24
# jours des moniteurs push d'Uptime Kuma.
locals {
  update_check_push_interval = 60 * 60 * 24 * 15

  update_check_hosts = {
    pve      = "Proxmox"
    docker   = "VM docker"
    pi       = "Raspberry Pi"
    flip     = "flip"
    pangolin = "Pangolin"
  }
}

resource "uptimekuma_monitor_push" "cron_updates" {
  for_each = local.update_check_hosts

  name = "Mises à jour ${each.value}"

  # Not a backup: grouped with the healthchecks. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval = local.update_check_push_interval

  # A pushed down pages at once. See uptime_globals.tf.
  max_retries    = local.push_down_max_retries
  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = local.alert_notification_ids
}

# Le moniteur de Proxmox, d'abord seul : déplacé, pas recréé, il garde son
# jeton push (celui que l'update-notify.env de pve contient déjà).
moved {
  from = uptimekuma_monitor_push.cron_pve_updates
  to   = uptimekuma_monitor_push.cron_updates["pve"]
}

output "uptime_cron_pve_updates_url" {
  description = "Proxmox - URL push du vérificateur des mises à jour en attente (update_notify, pve.yml)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_updates["pve"].push_token}"
  sensitive   = true
}

output "uptime_cron_docker_updates_url" {
  description = "VM docker - URL push du vérificateur des mises à jour en attente (update_notify, docker.yml)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_updates["docker"].push_token}"
  sensitive   = true
}

output "uptime_cron_pi_updates_url" {
  description = "Raspberry Pi - URL push du vérificateur des mises à jour en attente (update_notify, pi.yml)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_updates["pi"].push_token}"
  sensitive   = true
}

output "uptime_cron_flip_updates_url" {
  description = "flip - URL push du vérificateur des mises à jour en attente (update_notify, flip.yml)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_updates["flip"].push_token}"
  sensitive   = true
}

output "uptime_cron_pangolin_updates_url" {
  description = "Pangolin - URL push du vérificateur des mises à jour en attente (update_notify, pangolin.yaml)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_updates["pangolin"].push_token}"
  sensitive   = true
}
