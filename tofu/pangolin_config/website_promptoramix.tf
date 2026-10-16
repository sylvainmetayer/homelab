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
# most moves would be dropped by the catch-all `DROP COUNTRY ALL`. So the whole
# resource answers from anywhere: `/*` (which also matches `/`) is accepted in
# front of the country rules. A deliberate exception to "no bypass of a whole
# application" (path_bypasses_open_exactly_the_reviewed_paths): the HMAC check
# of every POST is what protects it, and /health discloses nothing. Turned into
# a rule by local.path_bypasses (rules.tf).
locals {
  promptoramix_public_paths = {
    "/*" = 2
  }
}

output "promptoramix_access_token" {
  description = "PROMPTORAMIX - Token d'accès pour les healthchecks"
  value       = local.healthcheck_access_tokens["promptoramix"]
  sensitive   = true
}
