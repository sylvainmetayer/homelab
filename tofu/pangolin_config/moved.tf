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
