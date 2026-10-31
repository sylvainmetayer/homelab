# Resource, target and monitors: local.websites (websites.tf).
#
# KitchenOwl: shopping list, recipes and meal planner, one account each. The
# web interface stays behind the SSO; the mobile app gets through the paths
# below.
locals {
  kitchenowl_website = {
    name      = "KitchenOwl"
    subdomain = "frigo"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "kitchenowl"
    backup    = true

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Vie perso"
      description = "Liste de courses, recettes et menus"
      icon        = "kitchenowl"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "kitchenowl"
      port    = 8080
      # Answers without an account and goes through Flask, not only through
      # uWSGI's static files (DISABLE_ONBOARDING: always {"onboarding": false}).
      hc_path = "/api/onboarding"
    }
  }
}

# The mobile app (Android, iOS) talks to the server with its own JWT, from
# wherever the phone is, and cannot pass the SSO wall: it never holds a
# Pangolin session. ACCEPT through local.path_bypasses (rules.tf), from any
# country like every path ACCEPT: a Pangolin rule matches on one criterion and
# the first match decides, so "this path, from FR or DE only" cannot be
# written - an ACCEPT behind the country PASS would never be reached. It keeps
# the app working on a trip too. The whole API, not a route list: the app
# calls every blueprint (kitchenowl/lib/services/api/*.dart), so a list would
# only spell `/api/*` out, and a release adding a blueprint would break the
# app silently (the `path_bypasses_open_exactly_the_reviewed_paths` test
# carries the exception). Read off the KitchenOwl v0.7.10 sources:
#
# - `/api/*`: the whole REST API (backend/app/api/register_controller.py
#   mounts every blueprint under /api), the uploaded images included
#   (/api/upload/<file>, kitchenowl/lib/widgets/image_provider.dart). Every
#   route but the ones below demands KitchenOwl's JWT (@jwt_required). Without
#   one: login (POST /api/auth), the server info (/api/health/<key> and its
#   /supported-languages), the OpenAPI description of the API (/api/openapi,
#   declared in backend/app/config.py, not in a controller), the onboarding
#   probe (always false: DISABLE_ONBOARDING, role kitchenowl) and the password
#   reset and mail confirmation routes, which need a mailed token and no SMTP
#   is configured; /api/auth/signup is only registered with OPEN_REGISTRATION,
#   off. A public recipe answers its public view without a token (GET
#   /api/recipe/<id>, visibility checked per recipe), and so do its images
#   (GET /api/upload/<file>, optional JWT: File.checkAuthorized lets through a
#   file of a recipe that is not private, nothing else). No rate limit on the
#   login: the passwords carry it.
# - `/socket.io/*`: live shopping-list updates. The app opens Socket.IO on
#   `<server>/api`, i.e. namespace /api over the default /socket.io path
#   (kitchenowl/lib/services/api/api_service.dart); the connect handler
#   demands the JWT (backend/app/sockets/connection_socket.py).
#
# Not opened: the web interface itself (`/`, the Flutter build), only useful
# with the SSO session it is served under, and /mcp, not even registered
# (KITCHENOWL_MCP_ENABLED unset).
locals {
  kitchenowl_mobile_paths = {
    "/api/*"       = 2
    "/socket.io/*" = 2
  }
}

output "uptime_backup_kitchenowl_url" {
  description = "KITCHENOWL - URL pour envoyer les heartbeats push"
  value       = local.backup_push_urls["kitchenowl"]
  sensitive   = true
}
