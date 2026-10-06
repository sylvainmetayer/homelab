# Resource, target and monitors: local.websites (websites.tf).
locals {
  immich_website = {
    name      = "Immich"
    subdomain = "photos"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "immich"
    backup    = true

    target = {
      site_id = pangolin_site.pi.id
      ip      = "immich_server"
      port    = 2283
    }
  }
}

resource "pangolin_resource_pincode" "immich" {
  resource_id = pangolin_resource.website["immich"].id
  pincode     = tostring(local.immich_pin)
}

# Priority 9: the last slot before the `PASS COUNTRY` rules generated in
# rules.tf (FR at 10, DE at 11). It used to sit at 12, just behind them, where
# it was never reached: the home connection is French, so the FR PASS matched
# first and sent it to the SSO wall like anybody else. Ahead of the country
# rules it does what it says - the home connection gets in by IP, without
# SSO. Only the backslash DROP of rules.tf (priority 1) comes before it.
#
# What that trusts, deliberately: every device behind the home connection
# (guest Wi-Fi included) gets Immich, Dawarich and TREK without SSO, and
# without Immich's pincode. And the address, not the house: if the ISP hands
# home_ip (secrets.sops.yaml) to someone else - a new lease, CGNAT - they get
# the same, until home_ip is updated AND pangolin_config applied (nothing
# applies it on a schedule). Change home_ip as soon as the line's IP changes.
resource "pangolin_resource_rule" "immich_home_ip" {
  resource_id = pangolin_resource.website["immich"].id
  action      = "ACCEPT"
  match       = "IP"
  value       = local.home_ip
  priority    = 9
  enabled     = true
}

output "immich_access_token" {
  description = "IMMICH - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["immich"]
  sensitive   = true
}

output "uptime_backup_immich_url" {
  description = "IMMICH - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["immich"]
  sensitive   = true
}
