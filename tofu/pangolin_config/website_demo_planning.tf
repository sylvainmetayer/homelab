# Public demo instance of Flip Planning, on its own server (site demo-planning,
# ansible/demo-planning.yml), deployed by the same Ansible role as the
# production one. This file mirrors website_flip_planning.tf: keep the two in
# step, and keep the `ip` values in step with flip_planning_container_prefix.
# No Mailpit exposed, no Borgmatic (the demo resets itself).
#
# Resource, targets and monitors: local.websites (websites.tf).
locals {
  demo_planning_website = {
    name      = "Demo Planning"
    subdomain = "demo-planning"
    domain_id = local.domain_ids["sylvain.dev"]

    # Public, open to every country (rule below), no SSO and so no role: the
    # demo's data is throwaway, reset every 30 minutes.
    sso     = false
    enabled = true

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      title       = "Démo planning"
      group       = "Flip Planning"
      description = "Démo publique du planning"
      icon        = "mdi-calendar-account"
    }

    # Catch-all target, must have a lower priority than the sub-path ones.
    target = {
      site_id  = pangolin_site.demo_planning.id
      ip       = "demo-planning"
      port     = 8080
      path     = "/"
      priority = 1
    }

    sub_targets = {
      # The demo declares no branding image (ansible/flip.yml leaves the
      # flip_planning_branding_* parameters at their empty defaults): its
      # assets directory is empty and the application shows no logo. The
      # nginx and this target stay, so that the two instances keep the same
      # shape and a demo that one day gets its own visuals needs no routing
      # change.
      #
      # Nothing to probe under /assets on an unbranded instance: nginx's own
      # default page answers on /, which is enough to tell the container is
      # up.
      assets = {
        site_id  = pangolin_site.demo_planning.id
        ip       = "demo-planning-assets"
        port     = 80
        path     = "/assets"
        priority = 4
      }
    }
  }
}

# Same path-based bypass as the production resource, and for the same reason:
# hosted assistants drive the MCP server and only Anthropic publishes a stable
# egress range, so matching on the caller would drop every other one on the
# catch-all `DROP COUNTRY ALL`. See the long comment in website_flip_planning.tf.
#
# The demo instance has its own PLANNING_MCP_API_KEY, so opening the prefix here
# does not open the production MCP server, and vice versa. Turned into a rule by
# local.path_bypasses (rules.tf).
locals {
  demo_planning_mcp_paths = {
    "/mcp/*" = 2
  }
}

output "demo_planning_access_token" {
  description = "DEMO_PLANNING - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["demo_planning"]
  sensitive   = true
}

# Open to every country: a PASS on every path skips the country rules (FR and DE
# only, rules.tf) and keeps Pangolin's authentication, which this resource has
# none of (sso = false). Priority 3, behind the `/mcp/*` ACCEPT at 2 (a tie
# must share the action, `tied_rules_share_their_action`). Not an ACCEPT: every
# ACCEPT goes through local.path_bypasses.
resource "pangolin_resource_rule" "demo_planning_worldwide" {
  resource_id = pangolin_resource.website["demo_planning"].id
  action      = "PASS"
  match       = "PATH"
  value       = "/*"
  priority    = 3
  enabled     = true
}
