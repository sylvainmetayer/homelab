# Appli pilote du stockage sur le NAS (fichiers + Postgres sur l'export NFS,
# sauvegardés par borg). Voir nas-storage-docker/homelab-storage-architecture.md.
#
# Resource, target and monitors: local.websites (websites.tf).
locals {
  nginx_demo_website = {
    name      = "Nginx Demo"
    subdomain = "nginx"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "nginx-demo"
    backup    = true

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "nginx-demo"
      port    = 80
    }
  }
}

output "nginx_demo_access_token" {
  description = "NGINX_DEMO - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["nginx_demo"]
  sensitive   = true
}

output "uptime_backup_nginx_demo_url" {
  description = "NGINX_DEMO - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["nginx_demo"]
  sensitive   = true
}
