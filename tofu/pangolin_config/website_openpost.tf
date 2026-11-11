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
# So: a media is public to whoever holds its URL, from the upload on, posted
# or not. How the files are named was NOT read off the sources at v7.38.6
# (path_bypass_images.json lists what to read): until then, treat an uploaded
# media as public. A Renovate bump of the image is never automerged.
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
