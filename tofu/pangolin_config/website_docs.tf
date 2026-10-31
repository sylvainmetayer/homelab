# Resource, target and monitors: local.websites (websites.tf).
#
# The repository's docs/ folder (runbooks, ADR, architecture...) as a static
# MkDocs site (Ansible role docs_site): read a runbook from a phone during an
# incident. Behind the SSO, its role `docs` with no member (Pangolin admins
# only), no path opened. Stateless, rebuilt from the repository: no backup.
locals {
  docs_website = {
    name      = "Documentation"
    subdomain = "docs"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "docs"

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Administration"
      description = "Runbooks, ADR et architecture du homelab"
      icon        = "mdi-book-open-variant"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "docs-site"
      port    = 8080
    }
  }
}
