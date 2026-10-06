# ---------------------------------------------------------------------------
# Proxmox web UI.
#
# Created by hand in the Pangolin UI long before this configuration existed and
# left out of it: it was pinned by id in the since-removed
# `local.unmanaged_resources` so the geo rules would still cover it, while the
# resource itself, its target and its Uptime Kuma monitor stayed outside the
# code. Declared here so all three are managed like every other public resource.
#
# Renamed from `00NTF - Proxmox`: the prefix stood for "00 - non terraform" and
# stopped being true once this block existed.
#
# Values mirror GET /v1/resource/4 and /v1/resource/4/targets, so the import
# was a no-op apart from the monitor (see the note in the entry below).
# Resource, access token and monitor: local.websites (websites.tf); the target,
# whose probe differs from every other one, stays here.
# ---------------------------------------------------------------------------

locals {
  proxmox_website = {
    name      = "Proxmox"
    subdomain = "proxmox"
    domain_id = local.domain_ids["sylvain.cloud"]

    # apply_rules (true on every entry) was false in Pangolin and first
    # mirrored as such, which left the country rules rules.tf creates for this
    # resource in place but never evaluated: the hypervisor UI answered from
    # any country, behind the SSO only. Enforced since, like on every other
    # public resource (pinned by the `every_public_resource_applies_its_rules`
    # test).
    #
    # The live monitor (id 56) carries a hand-made access token, sits in the
    # old "Auto-Hébergé" group and has no notification attached at all - it
    # has never been able to page anyone. It is not imported: a fresh token and
    # monitor built to the same shape as the other sixteen is what "rapatrier"
    # means here. Delete monitor 56 and its access token once this is applied.
  }
}

resource "pangolin_target" "proxmox" {
  resource_id = pangolin_resource.website["proxmox"].id
  site_id     = pangolin_site.proxmox_lxc.id
  ip          = "pve.sylvain.cloud"
  port        = 8006
  method      = "https"
  priority    = 100

  # Probe settings copied from the live target rather than normalised to the
  # 30s / 2 / 3 used elsewhere in this directory: this is an import, and a
  # tighter probe on the hypervisor UI is a deliberate choice worth keeping.
  #
  # `hc_status` is left undeclared: Pangolin holds null (accept any status) and
  # an optional+computed attribute cannot be pinned to null. Setting it to 200
  # would tighten the probe on a resource being imported blind - a separate,
  # explicit decision.
  hc_enabled             = true
  hc_scheme              = "https"
  hc_mode                = "http"
  hc_hostname            = "pve.sylvain.cloud"
  hc_port                = 8006
  hc_path                = "/"
  hc_method              = "GET"
  hc_interval            = 5
  hc_unhealthy_interval  = 30
  hc_timeout             = 5
  hc_healthy_threshold   = 1
  hc_unhealthy_threshold = 1
  hc_follow_redirects    = true
  hc_tls_server_name     = ""
}
