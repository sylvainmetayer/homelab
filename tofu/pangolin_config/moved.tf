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
  from = pangolin_resource_rule.block_country["15-00NTF - BBOX"]
  to   = pangolin_resource_rule.block_country["00NTF - BBOX"]
}

moved {
  from = pangolin_resource_rule.block_country["2-00NTF - Dashboard Traefik"]
  to   = pangolin_resource_rule.block_country["00NTF - Dashboard Traefik"]
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
  from = pangolin_resource_rule.block_country["38-SSH PI"]
  to   = pangolin_resource_rule.block_country["SSH PI"]
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

