# Gramps is stopped on purpose (gramps_enabled: false in
# ansible/host_vars/docker/variables.yaml, data and role kept). This one local
# says so for the whole file: Pangolin stops serving the resource rather than
# showing the maintenance page to whoever still has the link, and the
# healthcheck monitor, which could only be DOWN, is paused. The resource stays
# in local.managed_resources: its country rules stay in place for the day it
# comes back, and the coverage audit only looks at enabled resources anyway.
# A test pins it to gramps_enabled; flip both together.
locals {
  gramps_enabled = false
}

# Resource, target and monitors: local.websites (websites.tf).
locals {
  gramps_website = {
    name      = "Gramps"
    subdomain = "trees"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "gramps"
    backup    = true

    # Overrides the pin: see local.gramps_enabled above. Also pauses the
    # healthcheck monitor (websites.tf), which could only be DOWN; the backup
    # monitor stays active, the backup still running every night.
    enabled = local.gramps_enabled

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "grampsweb"
      port    = 5000
    }
  }
}

output "gramps_access_token" {
  description = "GRAMPS - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["gramps"]
  sensitive   = true
}

output "uptime_backup_gramps_url" {
  description = "GRAMPS - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["gramps"]
  sensitive   = true
}
