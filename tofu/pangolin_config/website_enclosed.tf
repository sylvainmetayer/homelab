# Resource, target and monitors: local.websites (websites.tf).
#
# Enclosed: end-to-end encrypted notes, deleted after reading (role enclosed),
# used to hand a renewed token or key over as a link: the secret is encrypted
# in the browser or by enclosed-share on the docker VM, the key only travels
# in the link's fragment (never sent to the server). Creation stays behind the
# SSO (no Enclosed account: PUBLIC_IS_AUTHENTICATION_REQUIRED=false), reading
# a note is open from anywhere through the paths below. Ephemeral secrets on
# purpose: no backup.
locals {
  enclosed_website = {
    name      = "Enclosed"
    subdomain = "pwpush"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "enclosed"

    # Its link on Homepage (homepage_links output, website_homepage.tf): the
    # creation form, behind the SSO.
    homepage = {
      group       = "Administration"
      description = "Secrets partagés par lien chiffré, lus une fois"
      icon        = "mdi-lock-clock"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "enclosed"
      port    = 8787
      # {"status":"ok"}, the route the image's own healthcheck also calls.
      hc_path = "/api/ping"
    }
  }
}

# Reading a note, from any country and without the SSO wall: these ACCEPTs,
# made by local.path_bypasses (rules.tf), sit in the 2 - 9 band in front of
# the country rules. Read off the Enclosed v1.16.1 sources:
# packages/app-server/src/index.node.ts (static files, then index.html for
# every path outside /api/), modules/app/server.ts and modules/notes/
# notes.routes.ts (the API), packages/app-client/src/routes.tsx and
# modules/notes/notes.services.ts (what the note page requests).
#
# A link is https://pwpush.sylvain.cloud/<noteId>#dar:<key>. The note id is a
# lowercase ULID (shared/utils/random.ts): 26 characters, the first ten the
# creation time in milliseconds, so it starts with `0` until the year 3084 -
# with `01` today. The page then makes two calls, GET /api/notes/<id>/exists
# and GET /api/notes/<id> (which deletes a note read once); the public config
# is inlined in index.html (window.__CONFIG__), no /api/config call.
#
# Pangolin's matcher (server/lib/pathMatch.ts, Pangolin 1.25.3): a bare `*`
# segment matches zero or more segments, so `/api/notes/*` would also match
# `/api/notes` - the creation route, POST /api/notes (Pangolin rules match
# paths, not methods). A `*` inside a segment (`0*`) is a glob on exactly one
# segment instead: `/api/notes/0*` needs a third segment and never matches
# `/api/notes`, `/api/notes/` or a path that resolves to it (`..`, `%2e%2e`
# and `%2F` are resolved before matching), the same for `/0*` and `/`. Only
# GET routes answer under these paths (Hono, strict routing): a POST to
# /api/notes/<id> is a 404, a POST to /0... gets index.html.
#
# Not opened, behind the SSO: `/` (the creation form), POST /api/notes (the
# creation), /api/config, /api/auth/login (authentication is off), /api/ping
# (the target probe, run by Newt from inside, and the Uptime Kuma monitor,
# through the healthcheck access token), the favicons and site.webmanifest
# (the page works without them; their requests are redirected to the SSO).
locals {
  enclosed_read_paths = {
    # The note page: index.html, the whole SPA shell (the creation form ships
    # in the same bundle; it is only useless without the API below). One
    # segment starting with `0`: a ULID.
    "/0*" = 2

    # Vite build output: the hashed JS and CSS bundles and the lazily loaded
    # locale chunks. The same bytes for every Enclosed 1.16.1 install. `*`
    # also matches /assets itself, which only answers index.html.
    "/assets/*" = 3

    # The two reads of the note page. The id is unguessable (80 random bits
    # after the timestamp) and the payload is ciphertext without the key of
    # the link's fragment; a note read once is deleted by the first GET.
    "/api/notes/0*"        = 4
    "/api/notes/0*/exists" = 4
  }
}

# Any path holding a backslash is dropped before the ACCEPTs above: see
# pangolin_resource_rule.backslash_guard in rules.tf, which covers every
# resource with a path rule.
