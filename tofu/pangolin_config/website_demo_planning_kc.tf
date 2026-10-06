# TEMPORARY third instance of Flip Planning, demo-planning-kc.sylvain.dev: the
# application pull request that makes Keycloak mandatory, tested on a real
# domain in HTTPS (passkeys need it) with its own Keycloak on the /auth
# sub-path. Deployed by the same Ansible role (ansible/flip.yml). Same shape as
# website_demo_planning.tf, minus what a test bench does not need: no MCP
# bypass, no healthcheck, no backup push monitor. Torn down with the
# remove-app skill once the pull request is merged.
#
# Resource and targets: local.websites (websites.tf). Same as the other two
# resources, `headers` is ignored: the provider cannot round-trip an emptied
# header list, so the attribute is never sent.
locals {
  demo_planning_kc_website = {
    name        = "Demo Planning KC"
    subdomain   = "demo-planning-kc"
    domain_id   = local.domain_ids["sylvain.dev"]
    role        = "demo-planning-kc"
    healthcheck = false

    # Catch-all target, must have a lower priority than the sub-path ones.
    target = {
      site_id  = pangolin_site.flip.id
      ip       = "demo-planning-kc"
      port     = 8080
      path     = "/"
      priority = 1
    }

    sub_targets = {
      pgadmin = {
        site_id  = pangolin_site.flip.id
        ip       = "demo-planning-kc-pgadmin"
        port     = 80
        path     = "/db"
        priority = 2
        hc_path  = "/db/misc/ping"
      }

      # Mailpit catches what BOTH the application and Keycloak send —
      # invitations, sign-in codes, resets — so /mail is where a tester reads
      # them. Behind the SSO, like the rest.
      mailpit = {
        site_id  = pangolin_site.flip.id
        ip       = "demo-planning-kc-mailpit"
        port     = 8025
        path     = "/mail"
        priority = 3
        hc_path  = "/mail/livez"
      }

      assets = {
        site_id  = pangolin_site.flip.id
        ip       = "demo-planning-kc-assets"
        port     = 80
        path     = "/assets"
        priority = 4
      }

      # Keycloak, on /auth. Its health endpoints live on the management port
      # (9000), which KC_HTTP_RELATIVE_PATH prefixes too: /auth/health/ready,
      # not /health/ready.
      keycloak = {
        site_id  = pangolin_site.flip.id
        ip       = "demo-planning-kc-keycloak"
        port     = 8080
        path     = "/auth"
        priority = 5
        hc_port  = 9000
        hc_path  = "/auth/health/ready"
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Carving /auth out of this resource's Pangolin SSO.
#
# The resource is `sso = true`: Pangolin demands its own login before anything
# reaches the origin. For an identity provider that is a deadlock, and not only
# for the browser: the application fetches the realm's discovery document and
# signing keys at startup, through this public URL and with no session of any
# kind. Behind the SSO those come back as Pangolin's HTML login page instead of
# JSON, discovery fails and the APPLICATION DOES NOT START.
#
# ACCEPT lifts it — Pangolin evaluates rules before SSO, and an ACCEPT returns
# "allowed" without running any auth method. Priority 2, in the band that is
# evaluated BEFORE the country rules (rules.tf): those only PASS, and the flip
# server calls from behind Pangolin's own NAT (no public address of its own),
# a source the country rules cannot be trusted to PASS — a rule behind them
# might never be reached, and the application would still not start.
#
# Two consequences, deliberate: /auth is not geo-filtered, and the Keycloak
# admin console (/auth/admin) is reachable with Keycloak's own login as its only
# guard. Acceptable for a temporary bench whose master realm is not the one
# people sign in to; production would narrow this to /auth/realms and
# /auth/resources before copying it.
#
# `/auth/*` covers `/auth` itself as well as everything under it (a trailing
# `*` segment matches zero segments, see website_flip_planning.tf). Turned into
# a rule by local.path_bypasses (rules.tf).
locals {
  demo_planning_kc_keycloak_paths = {
    "/auth/*" = 2
  }
}
