# Resource, target and monitors: local.websites (websites.tf). No backup
# monitor: PairDrop is stateless (no volume).
#
# Behind the SSO, no path opened: PairDrop has no login of its own, and the
# SSO wall is what keeps strangers from seeing each other's devices. The
# browser needs HTTPS (clipboard, notifications, PWA, persistent pairing),
# which Pangolin's Traefik provides. WebSocket upgrades (the signalling
# channel) pass through Traefik with no setting, and Traefik sets
# X-Forwarded-For, which PairDrop reads to group the devices of one public IP
# (upstream docs, "Host Your Own": a proxy must set it, or every client sees
# every other).
#
# Limit: no TURN server (not added on purpose). Transfers are WebRTC peer to
# peer with the public STUN of Google; two devices behind NATs that STUN
# cannot cross (4G/CGNAT on one side) may fail to connect. Same LAN works.
locals {
  pairdrop_website = {
    name      = "PairDrop"
    subdomain = "pairdrop"
    domain_id = local.domain_ids["sylvain.cloud"]
    role      = "pairdrop"

    # Its link on Homepage (homepage_links output, website_homepage.tf).
    homepage = {
      group       = "Divers"
      description = "Envoyer fichiers et texte d'un appareil à l'autre"
      icon        = "pairdrop"
    }

    target = {
      site_id = pangolin_site.proxmox_docker.id
      ip      = "pairdrop"
      port    = 3000
    }
  }
}
