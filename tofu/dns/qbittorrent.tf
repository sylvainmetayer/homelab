# qBittorrent (ansible/roles/mediamanager, derrière gluetun, sur le NAS) en HTTPS :
# https://qbittorrent.sylvain.cloud (ou :8443), servi par le Traefik du NAS comme
# mediamanager.sylvain.cloud (mediamanager.tf) : A privé vers le NAS, qui prime
# sur le joker *.sylvain.cloud, client Pangolin dehors (pangolin_site_resource.qbittorrent,
# site nas, rôle mediamanager-admin, Sylvain seul), Blocky le laisse passer
# (blocky_rebinding_allowed_domains).
resource "ovh_domain_zone_record" "qbittorrent" {
  zone      = "sylvain.cloud"
  subdomain = "qbittorrent"
  fieldtype = "A"
  ttl       = 300
  target    = "192.168.1.137"
}
