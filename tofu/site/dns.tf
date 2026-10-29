# La zone sylvain.dev est chez OVH, avec un joker *.sylvain.dev vers Pangolin
# (tofu/dns/pangolin.tf) : cet enregistrement explicite le court-circuite.
# subdomain du projet = <nom>.pages.dev, ou <nom>-xxx.pages.dev si le nom est pris.
resource "ovh_domain_zone_record" "www" {
  zone      = var.domain_zone
  subdomain = var.subdomain
  fieldtype = "CNAME"
  ttl       = 300
  target    = "${cloudflare_pages_project.site.subdomain}."
}

# L'apex sylvain.dev (A vers Pangolin, redirection 301 vers www) est dans
# tofu/dns/pangolin.tf, à côté du joker : variable sylvain_dev_apex_to_pangolin.

# Handle Bluesky sur le domaine (variable bluesky_did) : vérifié par DNS, pas
# par HTTPS, à cause de la redirection de l'apex vers www. Guillemets dans la
# cible, comme tous les TXT de tofu/dns : OVH les ajoute, sans eux le plan ne
# serait jamais vide.
resource "ovh_domain_zone_record" "atproto" {
  count = var.bluesky_did == null ? 0 : 1

  zone      = var.domain_zone
  subdomain = "_atproto"
  fieldtype = "TXT"
  ttl       = 3600
  target    = "\"did=${var.bluesky_did}\""
}
