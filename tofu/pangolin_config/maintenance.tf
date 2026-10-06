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

# Healthchecks: inverted keyword on the title.
#
# Pangolin's automatic maintenance page is a Next.js server component proxied
# by a Traefik router at priority 2000, so a service that is completely down
# answers 200 with that page instead of failing. A plain status-code monitor
# reads that as UP and never sends the downtime mail - the exact alerting the
# maintenance page was added on top of.
#
# So every resource healthcheck is an uptimekuma_monitor_http_keyword with
# `keyword = local.maintenance.title` and `invert_keyword = true`: finding the
# title means DOWN. The title is rendered server-side into the HTML
# (src/app/maintenance-screen/page.tsx), so it is visible to a plain GET, and it
# is the same local the resources use, so editing the page text cannot leave
# the monitors matching a stale string. It must stay a string that appears
# nowhere in a healthy app's landing page.
#
# A monitor on something that serves no maintenance page (the Pangolin
# dashboard, an external site) stays a plain uptimekuma_monitor_http: there is
# no title to match, and a down service does fail there.
# ---------------------------------------------------------------------------

locals {
  maintenance = {
    enabled = true
    type    = "automatic"
    title   = "Service temporairement indisponible"
    message = "Ce service est momentanément hors ligne. Il redeviendra accessible dès que possible."
  }
}
