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
