# Remplissage du thin pool LVM de l'hôte Proxmox (local-lvm), données et
# métadonnées (rôle thin_pool_check, pve.yml). Beszel ne mesure que `/` de pve :
# un pool plein gèle la VM docker et le LXC newt sans qu'aucune alerte ne sonne.
# Le timer pousse ici toutes les 6 heures : up avec les pourcentages, down dès
# que le seuil (85 %) est atteint ou que lvs échoue. Un down page tout de suite
# (local.push_down_max_retries, uptime_globals.tf), Telegram et ntfy compris.
#
# Un jour : trois passages manqués passent, le quatrième page (sans battement,
# timer arrêté ou hôte éteint).
resource "uptimekuma_monitor_push" "cron_thin_pool" {
  name        = "Thin pool Proxmox"
  description = "Données et métadonnées du thin pool LVM de pve sous 85 % (thin-pool-check.timer, rôle thin_pool_check)."

  # Not a backup: grouped with the healthchecks. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval = 60 * 60 * 24

  # A pushed down pages at once. See uptime_globals.tf.
  max_retries    = local.push_down_max_retries
  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = local.alert_notification_ids
}

output "uptime_cron_pve_thin_pool_url" {
  description = "Proxmox - URL push du contrôle du thin pool (rôle thin_pool_check, pve.yml)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_thin_pool.push_token}"
  sensitive   = true
}
