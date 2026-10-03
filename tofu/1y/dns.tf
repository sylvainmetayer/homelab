# La zone sylvain.dev est chez OVH, avec un joker *.sylvain.dev vers Pangolin
# (tofu/dns/pangolin.tf) : cet enregistrement explicite le court-circuite.
# subdomain du projet = <nom>.pages.dev, ou <nom>-xxx.pages.dev si le nom est pris.
#
# r.sylvain.dev pointait jusque-là vers Netlify, avec un enregistrement créé à la
# main : l'importer avant le premier apply (README.md) pour qu'il bascule sur
# place, sans doublon ni coupure.
resource "ovh_domain_zone_record" "r" {
  zone      = var.domain_zone
  subdomain = var.subdomain
  fieldtype = "CNAME"
  ttl       = 300
  target    = "${cloudflare_pages_project.r.subdomain}."
}
