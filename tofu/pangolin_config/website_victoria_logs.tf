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

  # Agents that reach vmauth through this public resource: the two Hetzner
  # hosts. Those of the LAN (docker, pi, newt-lxc, nas) post to the port
  # vmauth publishes on the docker VM, without Pangolin.
  log_remote_agents = toset(["flip", "pangolin"])
}

# The agents' write endpoint (vmauth routes only this path for an agent
# account, ansible/roles/victoria_logs). PASS, not ACCEPT, as Beszel's
# `/api/beszel/agent-connect`: it skips the country rules (both agents arrive
# with a private source IP, Pangolin's own Traefik or flip through the NAT,
# which GeoLite2 places nowhere) but keeps Pangolin's authentication, here
# each agent's own access token below, sent as headers. Behind it vmauth still
# wants the agent's account (sops victoria_logs_agent_passwords), which can
# only write.
#
# Exact path, no wildcard: the query string (`_stream_fields`...) is not part
# of the match. Not in local.path_bypasses (not an ACCEPT), hence not in
# path_bypass_images.json: a route moved by a new version would cut the agents
# off, it would open nothing.
resource "pangolin_resource_rule" "victoria_logs_insert" {
  resource_id = pangolin_resource.website["victoria_logs"].id
  action      = "PASS"
  match       = "PATH"
  value       = "/insert/jsonline"
  priority    = 3
  enabled     = true
}

# One token per remote agent: a compromised host is revoked alone.
# `persist_session` stays false (default): the agent keeps no cookie.
resource "pangolin_resource_access_token" "log_agents" {
  for_each = local.log_remote_agents

  resource_id = pangolin_resource.website["victoria_logs"].id
  title       = "Log agent ${each.key}"
}

output "log_agent_access_tokens" {
  description = "VICTORIA LOGS - Jeton d'accès Pangolin de chaque agent de journaux distant (clé = inventory_hostname), lu par pangolin.yaml et flip.yml"
  value = {
    for host, token in pangolin_resource_access_token.log_agents :
    host => { id = token.id, token = token.token }
  }
  sensitive = true
}
