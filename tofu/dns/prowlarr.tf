# Prowlarr (ansible/roles/mediamanager, derrière gluetun, sur le NAS) en HTTPS :
# https://prowlarr.sylvain.cloud (ou :8443), servi par le Traefik du NAS comme
# mediamanager.sylvain.cloud (mediamanager.tf) : A privé vers le NAS, qui prime
# sur le joker *.sylvain.cloud, client Pangolin dehors (pangolin_site_resource.prowlarr,
# site nas, rôle mediamanager-admin, Sylvain seul), Blocky le laisse passer
# (blocky_rebinding_allowed_domains).
resource "ovh_domain_zone_record" "prowlarr" {
  zone      = "sylvain.cloud"
  subdomain = "prowlarr"
  fieldtype = "A"
  ttl       = 300
  target    = "192.168.1.137"
}
