# Postiz, social media scheduler (role postiz, on flip).
# Resource, target and monitors: local.websites (websites.tf).
locals {
  postiz_website = {
    name      = "Postiz"
    subdomain = "posts"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "postiz"
    backup    = true

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Divers"
      description = "Publications planifiées sur les réseaux sociaux"
      icon        = "postiz"
    }

    # The root redirects to /auth (307) for a visitor with no Postiz session,
    # which the probe (hc_status 200) and the monitor would read as down:
    # both read the login page, served without a session.
    monitor_path = "/auth/login"

    target = {
      site_id = pangolin_site.flip.id
      ip      = "postiz" # container_name, ansible/roles/postiz
      port    = 5000
      hc_path = "/auth/login"
    }
  }
}

# Instagram, Threads, TikTok and Facebook (photos) are handed the URL of a
# media and fetch it from their own servers: no SSO they could pass, and not
# from FR or DE. This ACCEPT, made by local.path_bypasses (rules.tf), opens
# the uploaded media and nothing else. The image's nginx serves /uploads/
# itself, never the application (var/docker/nginx.conf, v2.25.3: `alias
# /uploads/`, image and mp4 types only, nosniff, CSP sandbox, no autoindex),
# and the backend names each file with 32 random hex characters under
# /YYYY/MM/DD (upload/local.storage.ts) after sniffing its type.
#
# So: a media is public to whoever holds its URL, from the upload on, posted
# or not. A Renovate bump of the image is never automerged
# (path_bypass_images.json): nginx.conf and local.storage.ts are read again.
locals {
  postiz_upload_paths = {
    "/uploads/*" = 2
  }
}

output "uptime_backup_postiz_url" {
  description = "POSTIZ - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["postiz"]
  sensitive   = true
}
