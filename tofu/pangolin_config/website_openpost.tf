# OpenPost, social media scheduler (role openpost, on flip).
# Resource, target and monitors: local.websites (websites.tf).
locals {
  openpost_website = {
    name      = "OpenPost"
    subdomain = "posts"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "openpost"
    backup    = true

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Divers"
      description = "Publications planifiées sur les réseaux sociaux"
      icon        = "mdi-send-clock"
    }

    # The root serves the web app whatever the state of the server behind it:
    # probe and monitor read the health route (the image's own HEALTHCHECK).
    monitor_path = "/api/v1/health"

    target = {
      site_id = pangolin_site.flip.id
      ip      = "openpost" # container_name, ansible/roles/openpost
      port    = 8080
      hc_path = "/api/v1/health"
    }
  }
}

# Instagram, Threads, Facebook and TikTok are handed the URL of a media and
# fetch it from their own servers: no SSO they could pass, and not from FR or
# DE. This ACCEPT, made by local.path_bypasses (rules.tf), opens the media
# route (OPENPOST_MEDIA_URL) and nothing else; upstream asks for it
# (docs/self-hosting/reverse-proxy: « /media/ must return files without
# sign-in or an expiring link »).
#
# OpenPost's own authorisation still applies behind it (handlers/media.go,
# v7.42.2: serveMedia, authorizeMediaAccess): /media/<uuid v4>, its /thumb/*
# and /poster answer only a session or token with access to the workspace, or
# a link signed by the server (`sig` and `exp`, HMAC, mediasigner) - the one
# it hands to the networks. Without either: 401. A Renovate bump of the image
# is never automerged (path_bypass_images.json): that check is read again.
locals {
  openpost_media_paths = {
    "/media/*" = 2
  }
}

output "uptime_backup_openpost_url" {
  description = "OPENPOST - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["openpost"]
  sensitive   = true
}

# L'appli mobile d'OpenPost (Android) ne passe pas le mur SSO de Pangolin :
# elle envoie un jeton d'accès Pangolin dans ses en-têtes de proxy
# (Advanced à l'installation, ou Proxy headers dans le menu de l'espace de
# travail : P-Access-Token-Id / P-Access-Token, v7.42.2), en plus du login
# d'OpenPost. Tout le reste de la ressource reste derrière le SSO et le filtre
# FR/DE. Un jeton par appareil, révocable seul. Lecture :
# `tofu output -json openpost_client_access_tokens`.
#
# description et persist_session sont optionnels et calculés : déclarés, pour
# qu'un changement fait dans l'interface se voie au plan (AGENTS.md).
resource "pangolin_resource_access_token" "openpost_clients" {
  for_each = toset(["android"])

  resource_id     = pangolin_resource.website["openpost"].id
  title           = "${pangolin_resource.website["openpost"].name} ${each.key}"
  description     = "Appli mobile OpenPost (${each.key}), en-têtes de proxy"
  persist_session = false
}

output "openpost_client_access_tokens" {
  description = "OPENPOST - En-têtes Pangolin des clients (appli mobile)"
  value = {
    for client, token in pangolin_resource_access_token.openpost_clients : client => {
      "P-Access-Token-Id" = tostring(token.id)
      "P-Access-Token"    = token.token
    }
  }
  sensitive = true
}
