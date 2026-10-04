# Vérification Google Search Console de la propriété « Domaine » sylvain.dev,
# qui couvre aussi tous ses sous-domaines (ref.sylvain.dev…). À l'apex : un nom
# porteur d'un CNAME, comme ref, ne peut avoir aucun autre enregistrement.
resource "ovh_domain_zone_record" "sylvain_dev_google_site_verification" {
  zone      = "sylvain.dev"
  subdomain = ""
  fieldtype = "TXT"
  ttl       = 300
  target    = "\"google-site-verification=XROrcW2Xt6g7cyF4SDNyz08GZeMB90QlstI3SBnUsq0\""
}
