# Resource, target and monitors: local.websites (websites.tf).
#
# VictoriaLogs: the logs of every host, 30 days (Ansible role victoria_logs,
# docker VM). Its built-in interface (vmui, /select/vmui/) behind the SSO,
# with no path opened around it. The target is vmauth, in front of the
# storage: it asks for its own account (sops victoria_logs_ui_password) after
# the SSO, since anything on the newt network, or on the LAN through the
# published port, reaches it without Pangolin.
#
# No backup: logs are reproducible (every host keeps its journald) and losing
# them only loses history. Hence no `backup`, no push monitor, nothing in
# .github/restore-test/apps.json.
locals {
  victoria_logs_website = {
    name      = "VictoriaLogs"
    subdomain = "logs"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "victoria-logs"

    # Every path but /health answers 401 without the vmauth account: the
    # inverted-keyword monitor probes vmauth's own health route instead of
    # the root.
    monitor_path = "/health"

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Administration"
      description = "Journaux de tous les hôtes (30 jours)"
      icon        = "mdi-text-box-search-outline"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "victoria-logs-auth"
      port    = 8427
      # vmauth's own route, served without an account.
      hc_path = "/health"
    }
  }
}

output "victoria_logs_access_token" {
  description = "VICTORIA LOGS - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["victoria_logs"]
  sensitive   = true
}
