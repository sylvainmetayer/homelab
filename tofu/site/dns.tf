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

# Apex vers Pangolin, dont Traefik redirige en 301 vers www (variable
# pangolin_domain_redirects dans ansible/host_vars/pangolin). Pas d'AAAA :
# Pangolin n'expose qu'une IPv4.
resource "ovh_domain_zone_record" "apex" {
  count = var.apex_to_pangolin ? 1 : 0

  zone      = var.domain_zone
  subdomain = ""
  fieldtype = "A"
  ttl       = 300
  target    = local.pangolin_ip
}
