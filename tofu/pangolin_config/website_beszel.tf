# Beszel (issue #79) : le hub de supervision (rôle Ansible beszel, VM docker),
# derrière le SSO, plus son compte Beszel (mot de passe dans sops).
#
# Resource, target and monitors: local.websites (websites.tf).
locals {
  beszel_website = {
    name      = "Beszel"
    subdomain = "monitoring"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "beszel"
    backup    = true

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Administration"
      description = "Supervision des hôtes : CPU, mémoire, disques, conteneurs"
      icon        = "beszel"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "beszel"
      port    = 8090
      # PocketBase : 200 sans session, quand le hub sert.
      hc_path = "/api/health"
    }
  }

  # Agents qui joignent le hub par cette ressource publique : les deux hôtes
  # Hetzner. Ceux du LAN (docker, pi, newt-lxc, nas, pve) parlent au hub par le
  # port publié sur la VM docker (rôle beszel), sans passer par Pangolin.
  beszel_remote_agents = toset(["flip", "pangolin"])
}

# Point d'entrée WebSocket des agents (GET /api/beszel/agent-connect, hub
# v0.21.1 : internal/hub/api.go, agent/client.go). PASS, pas ACCEPT, sur le
# modèle du `/mcp` de TREK : il saute les règles pays mais garde
# l'authentification Pangolin, ici le jeton d'accès propre à chaque agent
# (ci-dessous), que l'agent envoie en en-têtes (HUB_HEADERS). Sans jeton, la
# requête n'atteint jamais le hub ; avec, Beszel exige encore le jeton de
# l'agent (X-Token), puis son empreinte, figée à la première connexion.
#
# Pourquoi sauter les règles pays : l'agent de Pangolin arrive sur son propre
# Traefik et celui de flip par le réseau privé Hetzner (NAT par Pangolin),
# tous deux avec une IP source privée, sans pays pour GeoLite2 : le
# `DROP COUNTRY ALL` les refuserait.
#
# Chemin exact, sans joker : il ne s'étend à rien d'autre. Pas dans
# local.path_bypasses (ce n'est pas un ACCEPT), donc pas dans
# path_bypass_images.json : une route déplacée par une nouvelle version
# couperait les agents, elle n'ouvrirait rien.
resource "pangolin_resource_rule" "beszel_agent_connect" {
  resource_id = pangolin_resource.website["beszel"].id
  action      = "PASS"
  match       = "PATH"
  value       = "/api/beszel/agent-connect"
  priority    = 3
  enabled     = true
}

# Un jeton par agent distant : un hôte compromis se révoque seul.
# `persist_session` reste à false (défaut) : l'agent n'a pas de cookie, une
# redirection de Badger vers l'URL sans jeton le renverrait au mur SSO.
resource "pangolin_resource_access_token" "beszel_agents" {
  for_each = local.beszel_remote_agents

  resource_id = pangolin_resource.website["beszel"].id
  title       = "Beszel agent ${each.key}"
}

output "beszel_agent_hub_headers" {
  description = "BESZEL - En-têtes HUB_HEADERS de chaque agent distant (clé = inventory_hostname), lus par pangolin.yaml et flip.yml"
  value = {
    for host, token in pangolin_resource_access_token.beszel_agents :
    host => "P-Access-Token-Id: ${token.id}, P-Access-Token: ${token.token}"
  }
  sensitive = true
}

output "uptime_backup_beszel_url" {
  description = "BESZEL - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["beszel"]
  sensitive   = true
}
