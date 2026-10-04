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
