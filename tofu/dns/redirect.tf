resource "ovh_domain_zone_redirection" "betisier" {
  zone      = "sylvainmetayer.fr"
  subdomain = "betisier"
  type      = "visiblePermanent"
  target    = "https://betisier.sylvain.dev"
}
