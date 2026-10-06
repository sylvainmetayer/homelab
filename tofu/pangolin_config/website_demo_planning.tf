# Demo instance of Flip Planning, deployed by the same Ansible role as the
# production one (ansible/flip.yml applies it twice). This file mirrors
# website_flip_planning.tf: keep the two in step, and keep the `ip` values in
# step with flip_planning_container_prefix.
#
# Resource, targets and monitors: local.websites (websites.tf). Same as the
# production resource, `headers` is ignored: the provider cannot round-trip an
# emptied header list, so the attribute is never sent.
locals {
  demo_planning_website = {
    name      = "Demo Planning"
    subdomain = "demo-planning"
    domain_id = local.domain_ids["sylvain.dev"]
    role      = "demo-planning"
    backup    = true

    # Catch-all target, must have a lower priority than the pgAdmin one.
    target = {
      site_id  = pangolin_site.flip.id
      ip       = "demo-planning"
      port     = 8080
      path     = "/"
      priority = 1
    }

    sub_targets = {
      # pgAdmin on the /db sub-path of the same resource, hence the same SSO /
      # role. SCRIPT_NAME=/db tells pgAdmin its root, so no path rewrite here.
      pgadmin = {
        site_id  = pangolin_site.flip.id
        ip       = "demo-planning-pgadmin"
        port     = 80
        path     = "/db"
        priority = 2
        hc_path  = "/db/misc/ping"
      }

      mailpit = {
        site_id  = pangolin_site.flip.id
        ip       = "demo-planning-mailpit"
        port     = 8025
        path     = "/mail"
        priority = 3
        hc_path  = "/mail/livez"
      }

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
        site_id  = pangolin_site.flip.id
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

output "uptime_backup_demo_planning_url" {
  description = "DEMO_PLANNING - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["demo_planning"]
  sensitive   = true
}
