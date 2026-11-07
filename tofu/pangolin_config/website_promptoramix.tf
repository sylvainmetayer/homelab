# Promptoramix, the AI bot of the Marmelab Linkx tournament (repository
# sylvainmetayer/promptoramix, tofu/github/repository_promptoramix.tf), on flip.
#
# Resource, target and monitors: local.websites (websites.tf). No backup
# monitor: the application keeps no state.
locals {
  promptoramix_website = {
    name      = "Promptoramix"
    subdomain = "promptoramix"
    domain_id = local.domain_ids["sylvain.cloud"]

    # No link on Homepage: the root only answers POSTs, a link would lead nowhere.
    homepage = null

    # Called by the tournament's servers (Supabase edge functions), not by a
    # browser: no SSO wall they could pass, so no role either. Every request is
    # signed with a secret shared with the tournament (LINKX_SECRET, HMAC
    # checked by the application), the application's own and only guard.
    sso = false

    # The root only takes POSTs (a GET gets a 405, DOWN for Uptime Kuma): the
    # monitor reads /health, which answers `ok`, like the Pangolin probe.
    monitor_path = "/health"

    target = {
      site_id = pangolin_site.flip.id
      ip      = "promptoramix" # container_name, ansible/roles/promptoramix
      port    = 8080
      hc_path = "/health"
    }
  }
}

# The callers are Supabase edge functions, which run in whichever region is
# closest and publish no stable egress range: behind the FR/DE country rules
# most moves would be dropped by the catch-all `DROP COUNTRY ALL`. So the one
# route the platform calls, `POST /coup` (the URL registered on Linkx), is
# accepted from anywhere in front of the country rules, and so is `/health`
# (Uptime Kuma, which discloses nothing). Pangolin matches the path only, not
# the HTTP method: `GET /coup` is let through too, the application answers 405.
# Turned into rules by local.path_bypasses (rules.tf).
#
# The resource has no SSO, so a path matching no ACCEPT would fall through the
# country rules and reach the application from FR and DE. Everything else is
# therefore dropped (promptoramix_drop, priority 3, right behind the ACCEPTs at
# 2: first match wins, ascending). Changing the URL registered on the platform
# means changing `/coup` here in the same apply.
locals {
  promptoramix_public_paths = {
    "/coup"   = 2
    "/health" = 2
  }
}

resource "pangolin_resource_rule" "promptoramix_drop" {
  resource_id = pangolin_resource.website["promptoramix"].id
  action      = "DROP"
  match       = "PATH"
  value       = "/*"
  priority    = 3
  enabled     = true
}
