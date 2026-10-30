# One SSO role per app, bound to its resource by pangolin_resource_role.website
# (websites.tf) through the `role` field of the app's local.websites entry
# (website_<app>.tf). `betisier` (a public resource, sso = false) and `meerkat`
# (an older slug of the since-removed meerkat-crm) were bound by nothing and
# are gone.
locals {
  apps = [
    "immich",
    "nextcloud",
    "monica",
    "homepage",
    "rss",
    "wiki",
    "paperless",
    "papra",
    "stirling-pdf",
    "flip-planning",
    "demo-planning",
    "demo-planning-kc",
    "dawarich",
    "trek",
    "karakeep",
    "kitchenowl",
    "homebox",
    "speedtest-tracker",
    "ntfy",
    "wishlist",
    "beszel",
    "victoria-logs"
  ]
}

resource "pangolin_role" "apps" {
  for_each    = toset(local.apps)
  name        = each.value
  description = "Role for ${each.value}"
}
