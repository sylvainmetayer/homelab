# One SSO role per app, bound to its resource by pangolin_resource_role.website
# (websites.tf) through the `role` field of the app's local.websites entry
# (website_<app>.tf). `betisier` (a public resource, sso = false) and `meerkat`
# (an older slug of the since-removed meerkat-crm) were bound by nothing and
# are gone.
locals {
  apps = [
    "immich",
    "immich-selfie-timelapse",
    "immich-swipe",
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
    "homebox",
    "speedtest-tracker",
    "ntfy",
    "wishlist",
    "grocy",
    "beszel",
    "victoria-logs",
    "docs",
    "enclosed",
    "healthlog"
  ]

  # Optional+computed : non déclarés, un rôle passé en SSH dans l'UI ne se voit pas
  # au plan. Aucun rôle d'app n'ouvre de session SSH : seul Admin le fait, et il
  # n'est pas géré ici. Le sudo vaut "none" pour la même raison, même si
  # allow_ssh = false le rend déjà sans effet.
  role_pins = {
    allow_ssh               = false
    ssh_sudo_mode           = "none"
    ssh_sudo_commands       = []
    ssh_create_home_dir     = true
    ssh_unix_groups         = []
    require_device_approval = false
  }
}

resource "pangolin_role" "apps" {
  for_each                = toset(local.apps)
  name                    = each.value
  description             = "Role for ${each.value}"
  allow_ssh               = local.role_pins.allow_ssh
  ssh_sudo_mode           = local.role_pins.ssh_sudo_mode
  ssh_sudo_commands       = local.role_pins.ssh_sudo_commands
  ssh_create_home_dir     = local.role_pins.ssh_create_home_dir
  ssh_unix_groups         = local.role_pins.ssh_unix_groups
  require_device_approval = local.role_pins.require_device_approval
}
