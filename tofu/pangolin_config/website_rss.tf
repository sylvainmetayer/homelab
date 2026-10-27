# Resource, target and monitors: local.websites (websites.tf).
locals {
  rss_website = {
    name      = "RSS"
    subdomain = "rss"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "rss"
    backup    = true

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
# SSO, they answer 503.
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

output "rss_access_token" {
  description = "RSS - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["rss"]
  sensitive   = true
}

output "uptime_backup_rss_url" {
  description = "RSS - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["rss"]
  sensitive   = true
}
