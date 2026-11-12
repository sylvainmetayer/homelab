# Resource, target and monitors: local.websites (websites.tf).
#
# Grocy: stock, shopping lists, recipes and meal plan, chores, batteries and
# equipment of the house. Behind the SSO, then Grocy's own login; no path
# opened around it. The Android app gets through with HTTP Basic credentials,
# Sylvain's local MCP server (scripts/grocy-mcp) with a Pangolin access token
# (both below).
locals {
  grocy_website = {
    name      = "Grocy"
    subdomain = "grocy"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "grocy"
    backup    = true
    # Grocy trusts Pangolin's Remote-User header (ansible/roles/grocy): every
    # PHP page needs it, and a probe carries none. robots.txt is served by
    # nginx without session: it proves the container answers, not PHP.
    monitor_path = "/robots.txt"

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Vie perso"
      description = "Stocks, courses, recettes et menus, tâches de la maison"
      icon        = "grocy"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "grocy"
      port    = 80
      # Static, no session (see monitor_path).
      hc_path = "/robots.txt"
    }
  }
}

# The Android app (patzly/grocy-android, 3.8.3) sends no custom header and so
# no Pangolin access token: its requests only carry the Grocy API key
# (GROCY-API-KEY) and, when the server URL holds `user:password@`, an
# `Authorization: Basic` header built from them
# (web/CustomJsonObjectRequest.java, web/RequestHeaders.java for the images).
# Pangolin's header authentication checks that header (badger, after the
# country rules, verifySession.ts in 1.25.3): the app enters with
# `https://mobile:<password>@grocy.sylvain.cloud`, nothing is opened to the
# world, the API stays behind the geo-filter, then Grocy's API key. Browsers
# keep the SSO: extended_compatibility (a Basic challenge instead of the
# login page) stays off.
#
# The password is alphanumeric (no `:`, `@` or `/` to break the URL the app
# parses) and `mobile:<password>` stays under 57 bytes: the app encodes it
# with Android's Base64.DEFAULT, which wraps every 76 characters (and ends the
# value with a newline: the `user:password@` URL was reported working when the
# app added it, grocy-android#273). Read the URL with
# `tofu output -raw grocy_mobile_server_url`.
#
# Not audited: access_inventory.tf lists the org's access tokens and roles,
# not the header authentications, and the provider cannot read the
# credentials back. One made by hand in the dashboard, or this password
# changed there, never shows in a plan.
resource "random_password" "grocy_mobile" {
  length  = 32
  special = false
}

# Optional+computed attribute declared (extended_compatibility), see
# README.md. A header auth removed in the dashboard is recreated by the next
# apply; a changed password is not seen: restore it with
# `tofu apply -replace=pangolin_resource_header_auth.grocy_mobile`.
resource "pangolin_resource_header_auth" "grocy_mobile" {
  resource_id            = pangolin_resource.website["grocy"].id
  user                   = "mobile"
  password               = random_password.grocy_mobile.result
  extended_compatibility = false
}

output "grocy_mobile_server_url" {
  description = "GROCY - URL du serveur pour l'appli Android (identifiants Basic de Pangolin)"
  value       = "https://${pangolin_resource_header_auth.grocy_mobile.user}:${random_password.grocy_mobile.result}@${pangolin_resource.website["grocy"].full_domain}"
  sensitive   = true
}

# Access token of the local MCP server (scripts/grocy-mcp): sent as the
# P-Access-Token-Id / P-Access-Token headers, on top of the Grocy API key. Not
# the header authentication above: that one is single per resource and shared
# with the phone, a token is revoked alone. The resource stays behind the SSO
# wall and the geo-filter for everything else. Read them with
# `tofu output -json grocy_client_access_tokens`.
resource "pangolin_resource_access_token" "grocy_clients" {
  for_each = toset(["claude-code"])

  resource_id = pangolin_resource.website["grocy"].id
  title       = "${pangolin_resource.website["grocy"].name} ${each.key}"
}

output "grocy_client_access_tokens" {
  description = "GROCY - En-têtes Pangolin des clients (serveur MCP local)"
  value = {
    for client, token in pangolin_resource_access_token.grocy_clients : client => {
      "P-Access-Token-Id" = tostring(token.id)
      "P-Access-Token"    = token.token
    }
  }
  sensitive = true
}

output "uptime_backup_grocy_url" {
  description = "GROCY - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["grocy"]
  sensitive   = true
}
