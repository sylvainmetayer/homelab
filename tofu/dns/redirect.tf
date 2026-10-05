resource "ovh_domain_zone_redirection" "betisier" {
  zone      = "sylvainmetayer.fr"
  subdomain = "betisier"
  type      = "visiblePermanent"
  target    = "https://betisier.sylvain.dev"
}

# Mémoire EPSI : redirigé par le Traefik de Pangolin (pangolin_domain_redirects
# dans ansible/host_vars/pangolin), qui répond aussi en HTTPS, contrairement à
# une redirection OVH.
resource "ovh_domain_zone_record" "memoire_epsi" {
  zone      = "sylvainmetayer.fr"
  subdomain = "memoire.epsi"
  fieldtype = "A"
  ttl       = 300
  target    = local.pangolin_ip
}
