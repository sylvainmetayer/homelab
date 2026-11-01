# MediaManager à l'essai (ansible/roles/mediamanager, sur le NAS) en HTTPS :
# https://mediamanager.sylvain.cloud (ou :8443), servi par le Traefik du NAS
# (ansible/roles/nas_proxy, certificat Let's Encrypt par DNS-01 OVH), comme
# media.sylvain.cloud (media.tf). Ce A vers l'IP *privée* du NAS prime sur le
# joker *.sylvain.cloud (pangolin.tf) : rien n'est exposé sur Internet. Dehors,
# le client Pangolin résout le même nom vers la ressource privée (alias de
# pangolin_site_resource.mediamanager, site nas, rôle mediamanager). À la
# maison, Blocky doit le laisser passer (blocky_rebinding_allowed_domains).
resource "ovh_domain_zone_record" "mediamanager" {
  zone      = "sylvain.cloud"
  subdomain = "mediamanager"
  fieldtype = "A"
  ttl       = 300
  target    = "192.168.1.137"
}
