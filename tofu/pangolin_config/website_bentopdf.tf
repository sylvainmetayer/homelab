# Resource, target and monitors: local.websites (websites.tf). No backup
# monitor: BentoPDF is stateless (static files, nothing stored).
#
# Behind the SSO, no path opened: a static nginx with no login of its own, the
# SSO wall is the only door. Every PDF operation runs in the visitor's browser.
locals {
  bentopdf_website = {
    name      = "BentoPDF"
    subdomain = "bentopdf"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "bentopdf"

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Documents"
      description = "Outils PDF dans le navigateur : fusion, découpe, OCR, conversions"
      icon        = "bentopdf"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "bentopdf"
      port    = 8080
    }
  }
}
