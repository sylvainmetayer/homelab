# CAA (RFC 8659) : quelles autorités peuvent délivrer un certificat pour les
# noms des quatre zones OVH. Procédure et inventaire : docs/runbooks/dmarc.md,
# section « CAA ».
#
# Qui délivre quoi (inventaire du 2026-10-28, openssl s_client et dig ; aucun
# CAA n'existait encore, rien à importer) :
# - Let's Encrypt : Traefik de Pangolin (HTTP-01, un certificat par nom, aucun
#   joker), Traefik du NAS (DNS-01, media et nas.sylvain.cloud), et PikaPods
#   pour budget.sylvain.cloud (CNAME posé hors Tofu vers *.pikapod.net, qui ne
#   publie aucun CAA : c'est donc celui de sylvain.cloud qui s'applique ;
#   Let's Encrypt YE1 au 2026-10-28, à revoir si PikaPods change d'autorité).
# - GitHub Pages (*.talks.sylvain.dev) n'est pas concerné : ces noms sont des
#   CNAME vers sylvainmetayer.github.io, dont le CAA (digicert, letsencrypt,
#   sectigo) s'applique à leur place (RFC 8659 §3, le CNAME est suivi).
# - Cloudflare Pages (ref, www, r et planning.sylvain.dev : tofu/ref, tofu/site,
#   tofu/1y, tofu/planning) :
#   Google Trust Services aujourd'hui (WE1), mais Cloudflare choisit seul entre
#   Let's Encrypt, Google Trust Services et SSL.com et peut changer au
#   renouvellement. Ces noms sont des CNAME vers *.pages.dev, qui ne publie
#   aucun CAA : la recherche remonte à l'apex sylvain.dev (RFC 8659 §3), dont
#   le CAA doit donc autoriser les trois, sinon le renouvellement échoue.
# - Ni les redirections web OVH (HTTP seulement) ni autodiscover/autoconfig
#   (CNAME vers infomaniak.com, certificat au nom d'Infomaniak) ne demandent
#   de certificat pour nos noms.
#
# Aucun joker n'est délivré nulle part : issuewild ";" les interdit sur chaque
# zone (sans issuewild, les issue s'appliqueraient aussi aux jokers).

locals {
  # Valeurs CAA documentées par Cloudflare
  # (developers.cloudflare.com/ssl/reference/certificate-authorities).
  cloudflare_pages_cas = ["letsencrypt.org", "pki.goog", "ssl.com"]

  caa_issuers = {
    "sylvainmetayer.fr" = ["letsencrypt.org"]
    "sylvain.dev"       = local.cloudflare_pages_cas
    "metayer.dev"       = ["letsencrypt.org"]
    "sylvain.cloud"     = ["letsencrypt.org"]
  }

  caa_records = merge(
    {
      for pair in flatten([
        for zone, cas in local.caa_issuers : [for ca in cas : { zone = zone, ca = ca }]
        ]) : "${pair.zone} issue ${pair.ca}" => {
        zone   = pair.zone
        target = "0 issue \"${pair.ca}\""
      }
    },
    { for zone in keys(local.caa_issuers) : "${zone} issuewild" => { zone = zone, target = "0 issuewild \";\"" } },
    # Même alias que les rapports DMARC (mail.tf) : déjà public, dédié aux
    # rapports automatiques. Peu de CA l'utilisent, aucun ne s'en sert pour
    # refuser.
    { for zone in keys(local.caa_issuers) : "${zone} iodef" => { zone = zone, target = "0 iodef \"${local.dmarc_rua}\"" } },
  )
}

resource "ovh_domain_zone_record" "caa" {
  for_each = local.caa_records

  zone      = each.value.zone
  subdomain = ""
  fieldtype = "CAA"
  ttl       = 300
  target    = each.value.target
}
