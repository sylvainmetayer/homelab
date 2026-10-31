# Resource, target and monitors: local.websites (websites.tf).
#
# Stirling-PDF: PDF tools (merge, split, OCR, conversions...) behind the SSO,
# without any login of its own (SECURITY_ENABLELOGIN=false, role
# stirling_pdf): the Pangolin SSO is the only door. Stateless, so no backup.
locals {
  stirling_pdf_website = {
    name      = "Stirling-PDF"
    subdomain = "pdf"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "stirling-pdf"

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Documents"
      description = "Outils PDF : fusion, découpe, OCR, conversions"
      icon        = "stirling-pdf"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "stirling-pdf"
      port    = 8080
      # The image's own healthcheck: {"status":"UP"} once Spring is ready.
      hc_path = "/api/v1/info/status"
    }
  }
}
