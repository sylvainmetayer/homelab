# Vérificateur S.M.A.R.T. (rôle smart_check) : usure et secteurs des disques de
# pve (SSD), du Pi (NVMe) et du NAS (deux disques durs listés, sdc en dehors). Il publie sur ntfy
# (topic scripts) sur une hausse d'un constat et pousse ici à chaque passage
# hebdomadaire : up avec un résumé, down si un disque est illisible ou si ntfy
# échoue. Sans battement (timer arrêté, hôte éteint), le moniteur passe au
# rouge. Beszel ne prévient que sur le verdict FAILED
# (docs/runbooks/sante-des-disques.md).
#
# Clé = l'hôte dans la sortie lue par son playbook
# (uptime_cron_<clé>_smart_url), valeur = son nom dans Uptime Kuma.
#
# Quinze jours : un passage manqué passe, pas deux. Sous le plafond de 24
# jours des moniteurs push d'Uptime Kuma.
locals {
  smart_check_push_interval = 60 * 60 * 24 * 15

  smart_check_hosts = {
    pve = "Proxmox"
    pi  = "Raspberry Pi"
    nas = "NAS"
  }
}

resource "uptimekuma_monitor_push" "cron_smart" {
  for_each = local.smart_check_hosts

  name = "S.M.A.R.T. ${each.value}"

  # Not a backup: grouped with the healthchecks. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval = local.smart_check_push_interval

  # A pushed down pages at once. See uptime_globals.tf.
  max_retries    = local.push_down_max_retries
  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = local.alert_notification_ids
}

output "uptime_cron_pve_smart_url" {
  description = "Proxmox - URL push du vérificateur S.M.A.R.T. (smart_check, pve.yml)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_smart["pve"].push_token}"
  sensitive   = true
}

output "uptime_cron_pi_smart_url" {
  description = "Raspberry Pi - URL push du vérificateur S.M.A.R.T. (smart_check, pi.yml)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_smart["pi"].push_token}"
  sensitive   = true
}

output "uptime_cron_nas_smart_url" {
  description = "NAS - URL push du vérificateur S.M.A.R.T. (smart_check, nas.yml)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_smart["nas"].push_token}"
  sensitive   = true
}
