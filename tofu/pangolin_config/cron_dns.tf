# Filtrage DNS du LAN (Blocky, rôle blocky, ADR 0012) : deux instances, sur le
# Pi (pi.yml) et sur le LXC newt (lxc.yml), que le DHCP de la Bbox annonce
# toutes les deux. Servies sur le LAN seulement : un moniteur DNS de cet Uptime
# Kuma (PikaPods) ne les joint pas. Chaque hôte interroge son Blocky toutes les
# 5 minutes (blocky-check.timer : un nom qui résout, un nom que les listes
# bloquent) et pousse up, ou down avec la raison.
#
# Clé = suffixe de la sortie lue par le playbook (uptime_cron_dns_<clé>_url).
# Quinze minutes : deux vérifications manquées passent, pas trois ; un down
# poussé passe d'abord en PENDING (max_retries) : un échec isolé, juste après
# un redémarrage, n'alerte pas. Telegram et ntfy, comme partout ailleurs.
locals {
  dns_check_hosts = {
    pi  = "Raspberry Pi"
    lxc = "LXC newt"
  }
}

resource "uptimekuma_monitor_push" "cron_dns" {
  for_each = local.dns_check_hosts

  name        = "DNS ${each.value}"
  description = "Blocky sur ${each.value} : résolution et blocage (blocky-check.timer, rôle blocky)."

  # Not a backup: grouped with the healthchecks. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval        = 60 * 15
  retry_interval  = 60 * 5
  max_retries     = 1
  resend_interval = 0
  upside_down     = false
  active          = true
  tags            = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = local.alert_notification_ids
}

output "uptime_cron_dns_pi_url" {
  description = "DNS - URL push de la vérification de Blocky sur le Pi (pi.yml)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_dns["pi"].push_token}"
  sensitive   = true
}

output "uptime_cron_dns_lxc_url" {
  description = "DNS - URL push de la vérification de Blocky sur le LXC newt (lxc.yml)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_dns["lxc"].push_token}"
  sensitive   = true
}
