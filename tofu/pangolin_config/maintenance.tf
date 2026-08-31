# ---------------------------------------------------------------------------
# Maintenance page.
#
# Pangolin decides per resource whether to serve its maintenance screen instead
# of proxying (server/private/lib/traefik/getTraefikConfig.ts):
#
#     if (resource.maintenanceModeEnabled) {
#       if (type === "forced")         showMaintenancePage = true;
#       else if (type === "automatic") showMaintenancePage = !hasHealthyServers;
#     }
#
# `automatic` is therefore dormant while a target is healthy and takes over the
# moment every target is down or its site is offline - which is the state that
# used to surface as Traefik's raw "no available server". `forced` would black
# out a healthy site, so it is never what this configuration wants.
#
# All five `maintenance_*` attributes are optional+computed, the same shape that
# left hc_scheme NULL on gramps and scanopy and cost two outages. Declaring them
# is what lets a plan compare them against a literal instead of accepting
# whatever the API happens to hold.
#
# `maintenance_estimated_time` is deliberately left undeclared: it is a free-form
# ETA string for a *planned* window, meaningless for an automatic page, and
# optional+computed attributes cannot be pinned to null. It is display-only and
# cannot affect routing, unlike the probe fields.
# ---------------------------------------------------------------------------

# The title doubles as the keyword of the uptimekuma_monitor_http_keyword
# monitors (inverted: matching it means DOWN), so it must stay a string that
# appears nowhere in a healthy app's landing page.
locals {
  maintenance = {
    enabled = true
    type    = "automatic"
    title   = "Service temporairement indisponible"
    message = "Ce service est momentanément hors ligne. Il redeviendra accessible dès que possible."
  }
}
