# Key migration for pangolin_resource_rule.block_country.
#
# The key used to be "${id}-${name}", but the id is unknown at plan time for a
# resource this configuration has not created yet, and for_each keys must be
# known. The key is now the name alone. Without these blocks every rule below
# would be destroyed and recreated instead of simply re-keyed.
#
# Homelable is deliberately absent: that resource was removed, so its leftover
# state entry is meant to be destroyed rather than moved.

moved {
  from = pangolin_resource_rule.block_country["12-00NTF - spliit"]
  to   = pangolin_resource_rule.block_country["00NTF - spliit"]
}

moved {
  from = pangolin_resource_rule.block_country["21-Betisier"]
  to   = pangolin_resource_rule.block_country["Betisier"]
}

moved {
  from = pangolin_resource_rule.block_country["22-Echo"]
  to   = pangolin_resource_rule.block_country["Echo"]
}

moved {
  from = pangolin_resource_rule.block_country["23-Immich Swipe"]
  to   = pangolin_resource_rule.block_country["Immich Swipe"]
}

moved {
  from = pangolin_resource_rule.block_country["24-Immich"]
  to   = pangolin_resource_rule.block_country["Immich"]
}

moved {
  from = pangolin_resource_rule.block_country["34-RSS"]
  to   = pangolin_resource_rule.block_country["RSS"]
}

moved {
  from = pangolin_resource_rule.block_country["35-Meerkat CRM"]
  to   = pangolin_resource_rule.block_country["Meerkat CRM"]
}

moved {
  from = pangolin_resource_rule.block_country["37-Monica CRM"]
  to   = pangolin_resource_rule.block_country["Monica CRM"]
}

moved {
  from = pangolin_resource_rule.block_country["4-00NTF - Proxmox"]
  to   = pangolin_resource_rule.block_country["00NTF - Proxmox"]
}

moved {
  from = pangolin_resource_rule.block_country["73-SearXNG"]
  to   = pangolin_resource_rule.block_country["SearXNG"]
}

moved {
  from = pangolin_resource_rule.block_country["74-Paperless-ngx"]
  to   = pangolin_resource_rule.block_country["Paperless-ngx"]
}

moved {
  from = pangolin_resource_rule.block_country["75-00NTF - NAS"]
  to   = pangolin_resource_rule.block_country["00NTF - NAS"]
}

moved {
  from = pangolin_resource_rule.block_country["76-Flip Planning"]
  to   = pangolin_resource_rule.block_country["Flip Planning"]
}

moved {
  from = pangolin_resource_rule.block_country["79-Dawarich"]
  to   = pangolin_resource_rule.block_country["Dawarich"]
}

moved {
  from = pangolin_resource_rule.block_country["80-Gramps"]
  to   = pangolin_resource_rule.block_country["Gramps"]
}

# ---------------------------------------------------------------------------
# The "00NTF" ("00 - non terraform") prefix was dropped once these four
# resources were declared in this configuration. The rule keys are the Pangolin
# names, so every one of them is re-keyed; without these blocks the twelve rules
# below would be destroyed and recreated instead of moved.
# ---------------------------------------------------------------------------

moved {
  from = pangolin_resource_rule.allow_countries["00NTF - Proxmox-FR"]
  to   = pangolin_resource_rule.allow_countries["Proxmox-FR"]
}

moved {
  from = pangolin_resource_rule.allow_countries["00NTF - Proxmox-DE"]
  to   = pangolin_resource_rule.allow_countries["Proxmox-DE"]
}

moved {
  from = pangolin_resource_rule.block_country["00NTF - Proxmox"]
  to   = pangolin_resource_rule.block_country["Proxmox"]
}

moved {
  from = pangolin_resource_rule.allow_countries["00NTF - NAS-FR"]
  to   = pangolin_resource_rule.allow_countries["NAS-FR"]
}

moved {
  from = pangolin_resource_rule.allow_countries["00NTF - NAS-DE"]
  to   = pangolin_resource_rule.allow_countries["NAS-DE"]
}

moved {
  from = pangolin_resource_rule.block_country["00NTF - NAS"]
  to   = pangolin_resource_rule.block_country["NAS"]
}

# The Karakeep-only backslash DROP became the generic guard of rules.tf, which
# covers every resource with a path rule. Same rule, new address: no recreate.
moved {
  from = pangolin_resource_rule.karakeep_backslash
  to   = pangolin_resource_rule.backslash_guard["Karakeep"]
}

# ---------------------------------------------------------------------------
# The standalone path ACCEPTs joined local.path_bypasses (rules.tf): the
# planning `/mcp/*` and KC `/auth/*` rules, Karakeep's public lists and TREK's
# OAuth surface. Same resource, same path, same priority, so each rule is only
# re-addressed; without these blocks all seventeen would be destroyed and
# recreated, leaving each path closed between the two.
# ---------------------------------------------------------------------------

moved {
  from = pangolin_resource_rule.flip_planning_mcp
  to   = pangolin_resource_rule.path_bypass["Flip Planning /mcp/*"]
}

moved {
  from = pangolin_resource_rule.demo_planning_mcp
  to   = pangolin_resource_rule.path_bypass["Demo Planning /mcp/*"]
}

moved {
  from = pangolin_resource_rule.demo_planning_kc_keycloak
  to   = pangolin_resource_rule.path_bypass["Demo Planning KC /auth/*"]
}

moved {
  from = pangolin_resource_rule.karakeep_public["/public/lists/*"]
  to   = pangolin_resource_rule.path_bypass["Karakeep /public/lists/*"]
}

moved {
  from = pangolin_resource_rule.karakeep_public["/_next/static/*"]
  to   = pangolin_resource_rule.path_bypass["Karakeep /_next/static/*"]
}

moved {
  from = pangolin_resource_rule.karakeep_public["/api/public/*"]
  to   = pangolin_resource_rule.path_bypass["Karakeep /api/public/*"]
}

moved {
  from = pangolin_resource_rule.karakeep_public["/api/trpc/publicBookmarks.getPublicBookmarksInList"]
  to   = pangolin_resource_rule.path_bypass["Karakeep /api/trpc/publicBookmarks.getPublicBookmarksInList"]
}

moved {
  from = pangolin_resource_rule.karakeep_public["/api/v1/rss/lists/*"]
  to   = pangolin_resource_rule.path_bypass["Karakeep /api/v1/rss/lists/*"]
}

moved {
  from = pangolin_resource_rule.trek_mcp_oauth["/.well-known/oauth-protected-resource/mcp"]
  to   = pangolin_resource_rule.path_bypass["TREK /.well-known/oauth-protected-resource/mcp"]
}

moved {
  from = pangolin_resource_rule.trek_mcp_oauth["/.well-known/oauth-protected-resource"]
  to   = pangolin_resource_rule.path_bypass["TREK /.well-known/oauth-protected-resource"]
}

moved {
  from = pangolin_resource_rule.trek_mcp_oauth["/.well-known/oauth-authorization-server"]
  to   = pangolin_resource_rule.path_bypass["TREK /.well-known/oauth-authorization-server"]
}

moved {
  from = pangolin_resource_rule.trek_mcp_oauth["/.well-known/oauth-authorization-server/mcp"]
  to   = pangolin_resource_rule.path_bypass["TREK /.well-known/oauth-authorization-server/mcp"]
}

moved {
  from = pangolin_resource_rule.trek_mcp_oauth["/.well-known/openid-configuration"]
  to   = pangolin_resource_rule.path_bypass["TREK /.well-known/openid-configuration"]
}

moved {
  from = pangolin_resource_rule.trek_mcp_oauth["/mcp/.well-known/oauth-protected-resource"]
  to   = pangolin_resource_rule.path_bypass["TREK /mcp/.well-known/oauth-protected-resource"]
}

moved {
  from = pangolin_resource_rule.trek_mcp_oauth["/mcp/.well-known/oauth-authorization-server"]
  to   = pangolin_resource_rule.path_bypass["TREK /mcp/.well-known/oauth-authorization-server"]
}

moved {
  from = pangolin_resource_rule.trek_mcp_oauth["/mcp/.well-known/openid-configuration"]
  to   = pangolin_resource_rule.path_bypass["TREK /mcp/.well-known/openid-configuration"]
}

moved {
  from = pangolin_resource_rule.trek_mcp_oauth["/oauth/token"]
  to   = pangolin_resource_rule.path_bypass["TREK /oauth/token"]
}

# ---------------------------------------------------------------------------
# The public apps' generic resources became for_each instances of
# websites.tf, keyed by the former resource name. Every former address is
# moved, so nothing is recreated: a new access token would break the monitor
# headers and the `*_access_token` outputs, a new push monitor the push URL
# that every backup job reads from this state, a new resource its id, hence
# every rule and token attached to it.
#
# Not moved, because their address did not change: the extra tokens
# (karakeep_clients, trek_mcp_clients), the rules, the Immich pincode, the
# NAS and Proxmox targets, cron_monica and backup_pangolin.
# ---------------------------------------------------------------------------

# pangolin_resource (21)

moved {
  from = pangolin_resource.betisier
  to   = pangolin_resource.website["betisier"]
}

moved {
  from = pangolin_resource.dawarich
  to   = pangolin_resource.website["dawarich"]
}

moved {
  from = pangolin_resource.demo_planning
  to   = pangolin_resource.website["demo_planning"]
}

moved {
  from = pangolin_resource.demo_planning_kc
  to   = pangolin_resource.website["demo_planning_kc"]
}

moved {
  from = pangolin_resource.echo
  to   = pangolin_resource.website["echo"]
}

moved {
  from = pangolin_resource.flip_planning
  to   = pangolin_resource.website["flip_planning"]
}

moved {
  from = pangolin_resource.gramps
  to   = pangolin_resource.website["gramps"]
}

moved {
  from = pangolin_resource.immich
  to   = pangolin_resource.website["immich"]
}

moved {
  from = pangolin_resource.immich_swipe
  to   = pangolin_resource.website["immich_swipe"]
}

moved {
  from = pangolin_resource.karakeep
  to   = pangolin_resource.website["karakeep"]
}

moved {
  from = pangolin_resource.meerkat_crm
  to   = pangolin_resource.website["meerkat_crm"]
}

moved {
  from = pangolin_resource.monica
  to   = pangolin_resource.website["monica"]
}

moved {
  from = pangolin_resource.nas
  to   = pangolin_resource.website["nas"]
}

moved {
  from = pangolin_resource.nextcloud
  to   = pangolin_resource.website["nextcloud"]
}

moved {
  from = pangolin_resource.paperless
  to   = pangolin_resource.website["paperless"]
}

moved {
  from = pangolin_resource.proxmox
  to   = pangolin_resource.website["proxmox"]
}

moved {
  from = pangolin_resource.rss
  to   = pangolin_resource.website["rss"]
}

moved {
  from = pangolin_resource.scanopy
  to   = pangolin_resource.website["scanopy"]
}

moved {
  from = pangolin_resource.searxng
  to   = pangolin_resource.website["searxng"]
}

moved {
  from = pangolin_resource.trek
  to   = pangolin_resource.website["trek"]
}

moved {
  from = pangolin_resource.wiki
  to   = pangolin_resource.website["wiki"]
}

# pangolin_resource_role (18)

moved {
  from = pangolin_resource_role.dawarich
  to   = pangolin_resource_role.website["dawarich"]
}

moved {
  from = pangolin_resource_role.demo_planning
  to   = pangolin_resource_role.website["demo_planning"]
}

moved {
  from = pangolin_resource_role.demo_planning_kc
  to   = pangolin_resource_role.website["demo_planning_kc"]
}

moved {
  from = pangolin_resource_role.echo
  to   = pangolin_resource_role.website["echo"]
}

moved {
  from = pangolin_resource_role.flip_planning
  to   = pangolin_resource_role.website["flip_planning"]
}

moved {
  from = pangolin_resource_role.gramps
  to   = pangolin_resource_role.website["gramps"]
}

moved {
  from = pangolin_resource_role.immich
  to   = pangolin_resource_role.website["immich"]
}

moved {
  from = pangolin_resource_role.immich_swipe
  to   = pangolin_resource_role.website["immich_swipe"]
}

moved {
  from = pangolin_resource_role.karakeep
  to   = pangolin_resource_role.website["karakeep"]
}

moved {
  from = pangolin_resource_role.meerkat_crm
  to   = pangolin_resource_role.website["meerkat_crm"]
}

moved {
  from = pangolin_resource_role.monica
  to   = pangolin_resource_role.website["monica"]
}

moved {
  from = pangolin_resource_role.nextcloud
  to   = pangolin_resource_role.website["nextcloud"]
}

moved {
  from = pangolin_resource_role.paperless
  to   = pangolin_resource_role.website["paperless"]
}

moved {
  from = pangolin_resource_role.rss
  to   = pangolin_resource_role.website["rss"]
}

moved {
  from = pangolin_resource_role.scanopy
  to   = pangolin_resource_role.website["scanopy"]
}

moved {
  from = pangolin_resource_role.searxng
  to   = pangolin_resource_role.website["searxng"]
}

moved {
  from = pangolin_resource_role.trek
  to   = pangolin_resource_role.website["trek"]
}

moved {
  from = pangolin_resource_role.wiki
  to   = pangolin_resource_role.website["wiki"]
}

# pangolin_target (29)

moved {
  from = pangolin_target.betisier
  to   = pangolin_target.website["betisier"]
}

moved {
  from = pangolin_target.dawarich
  to   = pangolin_target.website["dawarich"]
}

moved {
  from = pangolin_target.demo_planning
  to   = pangolin_target.website["demo_planning"]
}

moved {
  from = pangolin_target.demo_planning_pgadmin
  to   = pangolin_target.website["demo_planning_pgadmin"]
}

moved {
  from = pangolin_target.demo_planning_mailpit
  to   = pangolin_target.website["demo_planning_mailpit"]
}

moved {
  from = pangolin_target.demo_planning_assets
  to   = pangolin_target.website["demo_planning_assets"]
}

moved {
  from = pangolin_target.demo_planning_kc
  to   = pangolin_target.website["demo_planning_kc"]
}

moved {
  from = pangolin_target.demo_planning_kc_pgadmin
  to   = pangolin_target.website["demo_planning_kc_pgadmin"]
}

moved {
  from = pangolin_target.demo_planning_kc_mailpit
  to   = pangolin_target.website["demo_planning_kc_mailpit"]
}

moved {
  from = pangolin_target.demo_planning_kc_assets
  to   = pangolin_target.website["demo_planning_kc_assets"]
}

moved {
  from = pangolin_target.demo_planning_kc_keycloak
  to   = pangolin_target.website["demo_planning_kc_keycloak"]
}

moved {
  from = pangolin_target.echo
  to   = pangolin_target.website["echo"]
}

moved {
  from = pangolin_target.flip_planning
  to   = pangolin_target.website["flip_planning"]
}

moved {
  from = pangolin_target.flip_planning_pgadmin
  to   = pangolin_target.website["flip_planning_pgadmin"]
}

moved {
  from = pangolin_target.flip_planning_mailpit
  to   = pangolin_target.website["flip_planning_mailpit"]
}

moved {
  from = pangolin_target.flip_planning_assets
  to   = pangolin_target.website["flip_planning_assets"]
}

moved {
  from = pangolin_target.gramps
  to   = pangolin_target.website["gramps"]
}

moved {
  from = pangolin_target.immich
  to   = pangolin_target.website["immich"]
}

moved {
  from = pangolin_target.immich_swipe
  to   = pangolin_target.website["immich_swipe"]
}

moved {
  from = pangolin_target.karakeep
  to   = pangolin_target.website["karakeep"]
}

moved {
  from = pangolin_target.meerkat_crm
  to   = pangolin_target.website["meerkat_crm"]
}

moved {
  from = pangolin_target.monica
  to   = pangolin_target.website["monica"]
}

moved {
  from = pangolin_target.nextcloud
  to   = pangolin_target.website["nextcloud"]
}

moved {
  from = pangolin_target.paperless
  to   = pangolin_target.website["paperless"]
}

moved {
  from = pangolin_target.rss
  to   = pangolin_target.website["rss"]
}

moved {
  from = pangolin_target.scanopy
  to   = pangolin_target.website["scanopy"]
}

moved {
  from = pangolin_target.searxng
  to   = pangolin_target.website["searxng"]
}

moved {
  from = pangolin_target.trek
  to   = pangolin_target.website["trek"]
}

moved {
  from = pangolin_target.wiki
  to   = pangolin_target.website["wiki"]
}

# pangolin_resource_access_token (20)

moved {
  from = pangolin_resource_access_token.betisier
  to   = pangolin_resource_access_token.healthcheck["betisier"]
}

moved {
  from = pangolin_resource_access_token.dawarich
  to   = pangolin_resource_access_token.healthcheck["dawarich"]
}

moved {
  from = pangolin_resource_access_token.demo_planning
  to   = pangolin_resource_access_token.healthcheck["demo_planning"]
}

moved {
  from = pangolin_resource_access_token.echo
  to   = pangolin_resource_access_token.healthcheck["echo"]
}

moved {
  from = pangolin_resource_access_token.flip_planning
  to   = pangolin_resource_access_token.healthcheck["flip_planning"]
}

moved {
  from = pangolin_resource_access_token.gramps
  to   = pangolin_resource_access_token.healthcheck["gramps"]
}

moved {
  from = pangolin_resource_access_token.immich
  to   = pangolin_resource_access_token.healthcheck["immich"]
}

moved {
  from = pangolin_resource_access_token.immich_swipe
  to   = pangolin_resource_access_token.healthcheck["immich_swipe"]
}

moved {
  from = pangolin_resource_access_token.karakeep
  to   = pangolin_resource_access_token.healthcheck["karakeep"]
}

moved {
  from = pangolin_resource_access_token.meerkat_crm
  to   = pangolin_resource_access_token.healthcheck["meerkat_crm"]
}

moved {
  from = pangolin_resource_access_token.monica
  to   = pangolin_resource_access_token.healthcheck["monica"]
}

moved {
  from = pangolin_resource_access_token.nas
  to   = pangolin_resource_access_token.healthcheck["nas"]
}

moved {
  from = pangolin_resource_access_token.nextcloud
  to   = pangolin_resource_access_token.healthcheck["nextcloud"]
}

moved {
  from = pangolin_resource_access_token.paperless
  to   = pangolin_resource_access_token.healthcheck["paperless"]
}

moved {
  from = pangolin_resource_access_token.proxmox
  to   = pangolin_resource_access_token.healthcheck["proxmox"]
}

moved {
  from = pangolin_resource_access_token.rss
  to   = pangolin_resource_access_token.healthcheck["rss"]
}

moved {
  from = pangolin_resource_access_token.scanopy
  to   = pangolin_resource_access_token.healthcheck["scanopy"]
}

moved {
  from = pangolin_resource_access_token.searxng
  to   = pangolin_resource_access_token.healthcheck["searxng"]
}

moved {
  from = pangolin_resource_access_token.trek
  to   = pangolin_resource_access_token.healthcheck["trek"]
}

moved {
  from = pangolin_resource_access_token.wiki
  to   = pangolin_resource_access_token.healthcheck["wiki"]
}

# uptimekuma_monitor_http_keyword (20)

moved {
  from = uptimekuma_monitor_http_keyword.betisier
  to   = uptimekuma_monitor_http_keyword.healthcheck["betisier"]
}

moved {
  from = uptimekuma_monitor_http_keyword.dawarich
  to   = uptimekuma_monitor_http_keyword.healthcheck["dawarich"]
}

moved {
  from = uptimekuma_monitor_http_keyword.demo_planning
  to   = uptimekuma_monitor_http_keyword.healthcheck["demo_planning"]
}

moved {
  from = uptimekuma_monitor_http_keyword.echo
  to   = uptimekuma_monitor_http_keyword.healthcheck["echo"]
}

moved {
  from = uptimekuma_monitor_http_keyword.flip_planning
  to   = uptimekuma_monitor_http_keyword.healthcheck["flip_planning"]
}

moved {
  from = uptimekuma_monitor_http_keyword.gramps
  to   = uptimekuma_monitor_http_keyword.healthcheck["gramps"]
}

moved {
  from = uptimekuma_monitor_http_keyword.immich
  to   = uptimekuma_monitor_http_keyword.healthcheck["immich"]
}

moved {
  from = uptimekuma_monitor_http_keyword.immich_swipe
  to   = uptimekuma_monitor_http_keyword.healthcheck["immich_swipe"]
}

moved {
  from = uptimekuma_monitor_http_keyword.karakeep
  to   = uptimekuma_monitor_http_keyword.healthcheck["karakeep"]
}

moved {
  from = uptimekuma_monitor_http_keyword.meerkat_crm
  to   = uptimekuma_monitor_http_keyword.healthcheck["meerkat_crm"]
}

moved {
  from = uptimekuma_monitor_http_keyword.monica
  to   = uptimekuma_monitor_http_keyword.healthcheck["monica"]
}

moved {
  from = uptimekuma_monitor_http_keyword.nas
  to   = uptimekuma_monitor_http_keyword.healthcheck["nas"]
}

moved {
  from = uptimekuma_monitor_http_keyword.nextcloud
  to   = uptimekuma_monitor_http_keyword.healthcheck["nextcloud"]
}

moved {
  from = uptimekuma_monitor_http_keyword.paperless
  to   = uptimekuma_monitor_http_keyword.healthcheck["paperless"]
}

moved {
  from = uptimekuma_monitor_http_keyword.proxmox
  to   = uptimekuma_monitor_http_keyword.healthcheck["proxmox"]
}

moved {
  from = uptimekuma_monitor_http_keyword.rss
  to   = uptimekuma_monitor_http_keyword.healthcheck["rss"]
}

moved {
  from = uptimekuma_monitor_http_keyword.scanopy
  to   = uptimekuma_monitor_http_keyword.healthcheck["scanopy"]
}

moved {
  from = uptimekuma_monitor_http_keyword.searxng
  to   = uptimekuma_monitor_http_keyword.healthcheck["searxng"]
}

moved {
  from = uptimekuma_monitor_http_keyword.trek
  to   = uptimekuma_monitor_http_keyword.healthcheck["trek"]
}

moved {
  from = uptimekuma_monitor_http_keyword.wiki
  to   = uptimekuma_monitor_http_keyword.healthcheck["wiki"]
}

# uptimekuma_monitor_push (16)

moved {
  from = uptimekuma_monitor_push.backup_betisier
  to   = uptimekuma_monitor_push.backup["betisier"]
}

moved {
  from = uptimekuma_monitor_push.backup_dawarich
  to   = uptimekuma_monitor_push.backup["dawarich"]
}

moved {
  from = uptimekuma_monitor_push.backup_demo_planning
  to   = uptimekuma_monitor_push.backup["demo_planning"]
}

moved {
  from = uptimekuma_monitor_push.backup_flip_planning
  to   = uptimekuma_monitor_push.backup["flip_planning"]
}

moved {
  from = uptimekuma_monitor_push.backup_gramps
  to   = uptimekuma_monitor_push.backup["gramps"]
}

moved {
  from = uptimekuma_monitor_push.backup_immich
  to   = uptimekuma_monitor_push.backup["immich"]
}

moved {
  from = uptimekuma_monitor_push.backup_karakeep
  to   = uptimekuma_monitor_push.backup["karakeep"]
}

moved {
  from = uptimekuma_monitor_push.backup_meerkat_crm
  to   = uptimekuma_monitor_push.backup["meerkat_crm"]
}

moved {
  from = uptimekuma_monitor_push.backup_monica
  to   = uptimekuma_monitor_push.backup["monica"]
}

moved {
  from = uptimekuma_monitor_push.backup_nextcloud
  to   = uptimekuma_monitor_push.backup["nextcloud"]
}

moved {
  from = uptimekuma_monitor_push.backup_paperless
  to   = uptimekuma_monitor_push.backup["paperless"]
}

moved {
  from = uptimekuma_monitor_push.backup_rss
  to   = uptimekuma_monitor_push.backup["rss"]
}

moved {
  from = uptimekuma_monitor_push.backup_scanopy
  to   = uptimekuma_monitor_push.backup["scanopy"]
}

moved {
  from = uptimekuma_monitor_push.backup_searxng
  to   = uptimekuma_monitor_push.backup["searxng"]
}

moved {
  from = uptimekuma_monitor_push.backup_trek
  to   = uptimekuma_monitor_push.backup["trek"]
}

moved {
  from = uptimekuma_monitor_push.backup_wiki
  to   = uptimekuma_monitor_push.backup["wiki"]
}
