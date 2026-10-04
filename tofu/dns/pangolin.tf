resource "ovh_domain_zone_record" "sylvain_cloud" {
  zone      = "sylvain.cloud"
  subdomain = "*"
  fieldtype = "A"
  ttl       = 300
  target    = local.pangolin_ip
}

resource "ovh_domain_zone_record" "sylvain_cloud_root" {
  zone      = "sylvain.cloud"
  subdomain = ""
  fieldtype = "A"
  ttl       = 300
  target    = local.pangolin_ip
}

resource "ovh_domain_zone_record" "sylvain_dev" {
  zone      = "sylvain.dev"
  subdomain = "*"
  fieldtype = "A"
  ttl       = 300
  target    = local.pangolin_ip
}

# sylvain.dev est servi par Cloudflare Pages sur www (tofu/site), qui n'accepte
# pas un apex hors zone Cloudflare : l'apex pointe vers Pangolin, dont Traefik
# répond par une 301 vers www (pangolin_domain_redirects). Pas d'AAAA :
# Pangolin n'expose qu'une IPv4. Activé à la bascule, voir tofu/site/README.md.
resource "ovh_domain_zone_record" "sylvain_dev_root" {
  count = var.sylvain_dev_apex_to_pangolin ? 1 : 0

  zone      = "sylvain.dev"
  subdomain = ""
  fieldtype = "A"
  ttl       = 300
  target    = local.pangolin_ip
}
