# Resource, target and monitors: local.websites (websites.tf).
locals {
  rss_website = {
    name      = "RSS"
    subdomain = "rss"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "rss"
    backup    = true

    # FreshRSS's root answers 302 to /i/: monitoring "/" cost two requests per
    # probe (the redirect, followed). /i/ itself, a 200, is the one request.
    # Pangolin serves its maintenance page on any path, so the inverted
    # keyword still sees an outage.
    monitor_path = "/i/"

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      title       = "FreshRSS"
      group       = "Lecture"
      description = "Lecteur de flux RSS"
      icon        = "freshrss"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "rss"
      port    = 80
    }
  }
}

# Read in the browser only, mobile included: no client API, so no path is
# opened around the SSO wall. The Google Reader and Fever APIs are also turned
# off in FreshRSS itself (api_enabled, ansible/roles/rss): reached through the
# SSO, they answer 503. The one exception is Homepage's FreshRSS widget, over
# the newt network (rss_api_enabled, set when its SOPS key exists): still no
# path rule here, nothing outside newt reaches the API without the SSO.
#
# Deleting their two ACCEPTs (and the backslash guard that went with them) has
# to go through a targeted apply first: until it runs, the three rules are
# still live in Pangolin while no longer declared, so the rule inventory audit
# (terraform_data.rule_inventory, rules.tf) stops every full plan. A targeted
# apply leaves that audit out of the graph (it depends on the rules, not the
# other way round). Once, from tofu/pangolin_config, then a normal plan:
#
#   tofu apply \
#     -target='pangolin_resource_rule.path_bypass["RSS /api/greader.php/*"]' \
#     -target='pangolin_resource_rule.path_bypass["RSS /api/fever.php"]' \
#     -target='pangolin_resource_rule.backslash_guard["RSS"]'
#
# This paragraph can go once that apply has run.

output "uptime_backup_rss_url" {
  description = "RSS - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["rss"]
  sensitive   = true
}
