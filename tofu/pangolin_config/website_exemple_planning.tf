# Public showcase of Planning Équipes, exemple-planning.sylvain.dev: the
# instance the product's web page links to. Deployed by the same Ansible role
# as production (ansible/flip.yml, applies flip_planning once per instance), on
# fictional data reset every night to a pre-solved reference database. Keep the
# `ip` values in step with flip_planning_container_prefix.
#
# Resource, targets and monitors: local.websites (websites.tf). What sets it
# apart from website_demo_planning.tf, which it otherwise mirrors:
#
# - `sso = false`, hence no role. A prospect follows a link from the web page
#   and lands on the application's own login, whose password the page prints.
#   The country rules still apply (rules.tf), like on every resource.
# - No pgAdmin target (the instance runs without it) and no /db route.
# - DROP rules on what a visitor holding the admin password must not reach, in
#   the band evaluated before the country rules (priorities 2 - 9, see
#   rules.tf): ahead of them because those only PASS, and a DROP behind a PASS
#   would never be read.
# - No Borg backup, hence no push monitor: the database is dropped every night.
locals {
  exemple_planning_website = {
    name      = "Exemple Planning"
    subdomain = "exemple-planning"
    domain_id = local.domain_ids["sylvain.dev"]
    sso       = false

    # Catch-all target, must have a lower priority than the sub-path ones.
    target = {
      site_id  = pangolin_site.flip.id
      ip       = "exemple-planning"
      port     = 8080
      path     = "/"
      priority = 1
    }

    sub_targets = {
      # Mailpit, public on purpose: it is where a visitor reads the mails the
      # showcase "sent" - a planning, an espace access code - since none leaves
      # the host. Everything in it is fictional and emptied every night.
      mailpit = {
        site_id  = pangolin_site.flip.id
        ip       = "exemple-planning-mailpit"
        port     = 8025
        path     = "/mail"
        priority = 3
        hc_path  = "/mail/livez"
      }

      # No branding image, but the nginx and this target stay so that every
      # instance keeps the same shape. See website_demo_planning.tf.
      assets = {
        site_id  = pangolin_site.flip.id
        ip       = "exemple-planning-assets"
        port     = 80
        path     = "/assets"
        priority = 4
      }
    }
  }
}

# What the shared admin password must not open, path by path. The application
# would let an administrator do each of these; on an instance whose
# administrator is anyone who read the web page, they stop at the proxy.
# Priority 1 belongs to the backslash guard (rules.tf), alone in its slot.
locals {
  exemple_planning_dropped_paths = {
    # The MCP server. The instance has no API key, so the application already
    # answers 401; dropping it here keeps the endpoint from being probed at all.
    mcp = { priority = 2, value = "/mcp/*" }
    # The SQL dump routes. The import accepts INSERT/DELETE/TRUNCATE on the
    # application's tables only, but an INSERT ... SELECT can still call any
    # function, and the compose stack's database user is a PostgreSQL
    # superuser: server-side file reads and writes are one statement away.
    database = { priority = 3, value = "/api/database/*" }
    # Outgoing webhooks: a public form that makes the host send signed HTTPS
    # requests to any address a visitor types in.
    webhooks = { priority = 4, value = "/api/webhooks/*" }
    # The synchronous solve takes a whole problem in its body and is not what
    # the UI calls (it uses /api/solve/async*, under the 60 s ceiling and the
    # one-job queue). No wildcard: only that exact path.
    solve_sync = { priority = 5, value = "/api/solve" }
    # Mailpit's send API: /mail is public so that visitors can READ what the
    # showcase sent; the send endpoint would let anyone post arbitrary HTML
    # into that inbox, served under this domain.
    mailpit_send = { priority = 6, value = "/mail/api/v1/send" }
  }
}

resource "pangolin_resource_rule" "exemple_planning_drop" {
  for_each = local.exemple_planning_dropped_paths

  resource_id = pangolin_resource.website["exemple_planning"].id
  action      = "DROP"
  match       = "PATH"
  value       = each.value.value
  priority    = each.value.priority
  enabled     = true
}

output "exemple_planning_access_token" {
  description = "EXEMPLE_PLANNING - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["exemple_planning"]
  sensitive   = true
}
