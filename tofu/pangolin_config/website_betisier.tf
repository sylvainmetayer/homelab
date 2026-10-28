# Resource, target and monitors: local.websites (websites.tf).
locals {
  betisier_website = {
    name      = "Betisier"
    subdomain = "betisier"
    domain_id = local.domain_ids["sylvain.dev"]

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Divers"
      description = "Bêtisier, application de TP publique"
      icon        = "mdi-emoticon-lol-outline"
    }

    # The only public resource without the SSO wall, so no role either: the
    # application is its own and only guard.
    sso    = false
    backup = true

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "betisier"
      port    = 80
    }
  }
}

output "betisier_access_token" {
  description = "BETISIER - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["betisier"]
  sensitive   = true
}

output "uptime_backup_betisier_url" {
  description = "BETISIER - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["betisier"]
  sensitive   = true
}

# Remise à zéro quotidienne de la démo (betisier-reset.timer, rôle betisier,
# docker.yml) : un succès pousse ici. Un reset raté laisse en ligne ce que les
# visiteurs de la veille ont saisi. Deux jours et une heure : une nuit manquée
# (VM éteinte, rattrapée par Persistent=true) passe, pas deux.
resource "uptimekuma_monitor_push" "cron_betisier_reset" {
  name = "Reset ${pangolin_resource.website["betisier"].name}"

  # Not a backup: grouped with the healthchecks. See uptime_globals.tf.
  parent = uptimekuma_monitor_group.self_hosted.id

  interval = 60 * 60 * 49

  retry_interval = 20
  active         = true
  tags           = [local.tofu_tag, { tag_id : uptimekuma_tag.self_hosted.id }]

  notification_ids = [uptimekuma_notification_smtp.email.id]
}

output "uptime_cron_betisier_reset_url" {
  description = "BETISIER - URL push de la remise à zéro quotidienne (betisier-reset)"
  value       = "${local.uptimekuma_endpoint}/api/push/${uptimekuma_monitor_push.cron_betisier_reset.push_token}"
  sensitive   = true
}
