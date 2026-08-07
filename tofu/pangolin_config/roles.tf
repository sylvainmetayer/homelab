locals {
  apps = [
    "immich",
    "meerkat-crm",
    "nextcloud",
    "betisier",
    "echo",
    "meerkat",
    "monica",
    "rss",
    "searxng",
    "semaphore",
    "wiki",
    "paperless",
    "flip-planning",
    "homelable",
    "gramps",
    "dawarich",
    "scanopy",
    "trek"
  ]
}

resource "pangolin_role" "apps" {
  for_each    = toset(local.apps)
  name        = each.value
  description = "Role for ${each.value}"
}
