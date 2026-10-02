# La zone sylvain.dev est chez OVH, avec un joker *.sylvain.dev vers Pangolin
# (tofu/dns/pangolin.tf) : cet enregistrement explicite le court-circuite.
# subdomain du projet = <nom>.pages.dev, ou <nom>-xxx.pages.dev si le nom est pris.
resource "ovh_domain_zone_record" "ref" {
  zone      = var.domain_zone
  subdomain = var.subdomain
  fieldtype = "CNAME"
  ttl       = 300
  target    = "${cloudflare_pages_project.ref.subdomain}."
}

# Vérification Google Search Console. Posée à l'apex et pas sur ref : un nom
# porteur d'un CNAME ne peut avoir aucun autre enregistrement. La propriété
# « Domaine » sylvain.dev couvre ref.sylvain.dev et les autres sous-domaines.
resource "ovh_domain_zone_record" "google_site_verification" {
  count = var.google_site_verification == null ? 0 : 1

  zone      = var.domain_zone
  subdomain = ""
  fieldtype = "TXT"
  ttl       = 300
  target    = "\"${var.google_site_verification}\""
}
