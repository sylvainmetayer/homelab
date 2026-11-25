# Resource, targets and monitors: local.websites (websites.tf).
locals {
  flip_planning_website = {
    name      = "Flip Planning"
    subdomain = "flip-planning"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "flip-planning"
    backup    = true

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Flip Planning"
      description = "Planning des équipes, production"
      icon        = "mdi-calendar-account"
    }

    # Catch-all target, must have a lower priority than the pgAdmin one.
    target = {
      site_id  = pangolin_site.flip.id
      ip       = "flip-planning"
      port     = 8080
      path     = "/"
      priority = 1
    }

    sub_targets = {
      # pgAdmin is served on the /db sub-path of the same resource, so it is
      # protected by the same SSO / role. pgAdmin is told about its root via
      # SCRIPT_NAME=/db, hence no path rewrite here.
      pgadmin = {
        site_id  = pangolin_site.flip.id
        ip       = "flip-planning-pgadmin"
        port     = 80
        path     = "/db"
        priority = 2
        hc_path  = "/db/misc/ping"
      }

      mailpit = {
        site_id  = pangolin_site.flip.id
        ip       = "flip-planning-mailpit"
        port     = 8025
        path     = "/mail"
        priority = 3
        hc_path  = "/mail/livez"
      }

      # The festival's visuals are part of the deployment, not of the image
      # (the application repository carries no customer mark). They are the
      # flip_planning_branding_* role parameters of this instance in
      # ansible/flip.yml: copied next to the compose file, mounted read-only on
      # the app container for the PDFs, and served to the browser by a small
      # nginx on this sub-path - same resource, so the same SSO and the same
      # role guard them.
      #
      # No dedicated probe endpoint on a static server: the logo itself is the
      # healthcheck, and it is exactly the file whose absence would break the
      # UI. Its name is the basename of flip_planning_branding_logo in
      # flip.yml.
      assets = {
        site_id  = pangolin_site.flip.id
        ip       = "flip-planning-assets"
        port     = 80
        path     = "/assets"
        priority = 4
        hc_path  = "/assets/flip.png"
      }

      # Keycloak, on /auth (KC_HTTP_RELATIVE_PATH). Its health endpoints live on
      # the management port (9000), which that prefix applies to as well:
      # /auth/health/ready, not /health/ready.
      keycloak = {
        site_id  = pangolin_site.flip.id
        ip       = "flip-planning-keycloak"
        port     = 8080
        path     = "/auth"
        priority = 5
        hc_port  = 9000
        hc_path  = "/auth/health/ready"
      }
    }
  }
}

# The MCP server (`POST /mcp`, `GET /mcp/sse`) is driven by hosted assistants -
# Claude, ChatGPT, Le Chat, Gemini. Only Anthropic publishes a stable egress
# range, which is why this used to be an ACCEPT on CIDR 160.79.104.0/21: every
# other assistant was dropped by the catch-all `DROP COUNTRY ALL` (priority 99,
# in rules.tf), and calling from FR/DE would not have helped either - the
# country rules only PASS, so the request landed on the SSO wall with no
# session to show it.
#
# Matching on the path instead of on the caller takes geography out of the
# question. Priority 2 puts this ahead of the country rules so it decides first
# whatever the origin - they only PASS, so a request from FR or DE would
# otherwise never reach it - and ACCEPT short-circuits authentication outright:
# Pangolin evaluates rules before SSO, and an ACCEPT returns "allowed" without
# running any auth method. It sits in the bypass band described in rules.tf,
# right behind the backslash DROP that holds priority 1 on every resource with
# a path rule.
#
# This opens /mcp to the internet as far as Pangolin is concerned; it does not
# open the MCP server. The application still demands its own shared key
# (PLANNING_MCP_API_KEY, header X-Api-Key) and answers 401 without it. The
# exposure is limited to that prefix: the UI, pgAdmin (/db), Mailpit (/mail)
# and the assets keep both the SSO wall and the geo-filter.
#
# `/mcp/*` covers `/mcp` itself as well as everything under it - Pangolin's
# matcher lets a trailing `*` segment match zero segments (server/lib/
# pathMatch.ts).
#
# Turned into a rule by local.path_bypasses (rules.tf), like every path ACCEPT.
locals {
  flip_planning_mcp_paths = {
    "/mcp/*" = 2
  }
}

# Keycloak, on /auth of the same resource: the identity provider of the
# application (realm `planning`, issuer
# https://flip-planning.sylvain.cloud/auth/realms/planning).
#
# The resource is `sso = true`: Pangolin demands its own login before anything
# reaches the origin. For an identity provider that is a deadlock, and not only
# for the browser: the application fetches the realm's discovery document and
# signing keys at startup, through this public URL and with no session of any
# kind. Behind the SSO those come back as Pangolin's HTML login page instead of
# JSON, discovery fails and the APPLICATION DOES NOT START. Hosted MCP clients
# (Claude on the web...) run the OAuth flow against the realm from outside FR
# and DE, with dynamic client registration, so they need it too.
#
# ACCEPT lifts it - Pangolin evaluates rules before SSO, and an ACCEPT returns
# "allowed" without running any auth method. Priority 2, in the band evaluated
# BEFORE the country rules (rules.tf): those only PASS, and the flip server
# calls from behind Pangolin's own NAT, a source the country rules cannot be
# trusted to PASS, while the MCP clients come from anywhere.
#
# Only what a sign-in needs, nothing of the administration:
#   /auth/realms/planning/*  discovery, JWKS, authorization, token, dynamic
#                            client registration, login pages. Keycloak's own
#                            login and client policies are the guard there.
#   /auth/resources/*        the stylesheets and scripts of the login page.
# NOT opened: /auth/realms/master/* and /auth/admin/*, so the admin console and
# the master realm stay behind the Pangolin SSO + PIN and the geo-filter.
#
# `/auth/realms/planning/*` covers the prefix itself as well as everything
# under it (a trailing `*` segment matches zero segments, see
# local.flip_planning_mcp_paths above). Turned into a rule by
# local.path_bypasses (rules.tf).
locals {
  flip_planning_keycloak_paths = {
    "/auth/realms/planning/*" = 2
    "/auth/resources/*"       = 2
  }
}

output "flip_planning_access_token" {
  description = "FLIP_PLANNING - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["flip_planning"]
  sensitive   = true
}

# PIN d'abord posé à la main dans l'interface, déclaré ici le 2026-11-11
# (audit des authentifications faites main, binding_inventory.tf).
resource "pangolin_resource_pincode" "flip_planning" {
  resource_id = pangolin_resource.website["flip_planning"].id
  # Write-only : le PIN n'entre ni dans le plan ni dans l'état. Il ne part vers
  # Pangolin que si pincode_wo_version change : nouveau PIN dans SOPS = version + 1.
  pincode_wo         = tostring(local.flip_planning_pin)
  pincode_wo_version = 1
}

output "uptime_backup_flip_planning_url" {
  description = "FLIP_PLANNING - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["flip_planning"]
  sensitive   = true
}
