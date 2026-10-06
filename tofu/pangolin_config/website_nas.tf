# ---------------------------------------------------------------------------
# NAS admin UI.
#
# Was `00NTF - NAS`, pinned by id in the since-removed local.unmanaged_resources.
# Declared here so the "00NTF" ("00 - non terraform") prefix could be dropped:
# see the runbook in the commit message - the live rename has to happen before
# this applies, or the coverage precondition in rules.tf fails on a name it no
# longer knows.
#
# Values mirror GET /v1/resource/75 and /v1/resource/75/targets. Resource,
# access token and monitor: local.websites (websites.tf); the target, which has
# no probe, stays here.
# ---------------------------------------------------------------------------

locals {
  nas_website = {
    name      = "NAS"
    subdomain = "nas"
    domain_id = local.domain_ids["sylvain.cloud"]

    # apply_rules (true on every entry) was false in Pangolin, mirrored at
    # first: the country rules existed but were never evaluated. Enforced
    # since - same history as Proxmox.
    #
    # The maintenance page (maintenance.tf) is inert as long as the target
    # below has no health check: Pangolin reads an unprobed target as
    # "unknown", not "unhealthy", so it never counts as down. Enabling hc_*
    # here would make both it and the monitor meaningful - a separate decision
    # on an infrastructure endpoint.
    #
    # Its monitor (inverted keyword on the maintenance title, see
    # maintenance.tf): the NAS answers 307 to /, Uptime Kuma follows
    # redirects by default and lands on /desktop/ with a 200.
  }
}

resource "pangolin_target" "nas" {
  resource_id = pangolin_resource.website["nas"].id
  site_id     = pangolin_site.proxmox_lxc.id
  ip          = "192.168.1.137"
  port        = 9999
  method      = "http"
  priority    = 100

  # No probe live, mirrored. See the note on the maintenance page above.
  hc_enabled = false
}
