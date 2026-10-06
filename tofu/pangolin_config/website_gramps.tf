# Resource, target and monitors: local.websites (websites.tf).
locals {
  gramps_website = {
    name      = "Gramps"
    subdomain = "trees"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "gramps"
    backup    = true

    # Overrides the pin: Gramps is stopped on purpose (gramps_enabled: false in
    # ansible/host_vars/docker/variables.yaml, data and role kept), so Pangolin
    # stops serving it rather than showing the maintenance page to whoever
    # still has the link. Still in local.managed_resources: its country rules
    # stay in place for the day it comes back, and the coverage audit only
    # looks at enabled resources anyway. Flip back to true together with
    # gramps_enabled.
    #
    # It also deactivates both monitors (websites.tf). The healthcheck could
    # only be DOWN and mailing. The backup monitor is the only exception to
    # "every backup monitor is active" in tests/invariants.tftest.hcl. Note
    # that gramps_backup_enabled stays true in host_vars: borgmatic still
    # archives the (frozen) data every night and its push to this inactive
    # monitor is refused, which borgmatic only logs as a warning - a failing
    # Gramps backup pages nobody until this is flipped back.
    enabled = false

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
