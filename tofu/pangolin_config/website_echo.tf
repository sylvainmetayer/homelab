# Resource, target and monitors: local.websites (websites.tf). No backup
# monitor.
locals {
  echo_website = {
    name      = "Echo"
    subdomain = "echo"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "echo"

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "echo"
      port    = 80
    }
  }
}

output "echo_access_token" {
  description = "ECHO - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["echo"]
  sensitive   = true
}
