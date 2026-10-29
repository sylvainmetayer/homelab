# La zone sylvain.dev est chez OVH, avec un joker *.sylvain.dev vers Pangolin
# (tofu/dns/pangolin.tf) : cet enregistrement explicite le court-circuite.
# subdomain du projet = <nom>.pages.dev, ou <nom>-xxx.pages.dev si le nom est
# pris. Sans le point final, OVH complèterait la cible avec la zone.
resource "ovh_domain_zone_record" "cname" {
  zone      = var.domain_zone
  subdomain = var.subdomain
  fieldtype = "CNAME"
  ttl       = 300
  target    = "${local.pages_project.subdomain}."
}
