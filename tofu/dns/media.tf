# Jellyfin (ansible/roles/jellyfin, sur le NAS) : une seule adresse,
# media.sylvain.cloud, servie par le Traefik du NAS avec un certificat Let's
# Encrypt obtenu par DNS-01 OVH. Ce A vers l'IP *privée* du NAS prime sur le
# joker *.sylvain.cloud (pangolin.tf), qui pointe Pangolin : un nom précis
# l'emporte toujours sur le joker. Rien n'est exposé sur Internet : hors de la
# maison, l'IP ne mène nulle part, et le client Pangolin résout le même nom
# vers la ressource privée (alias de pangolin_site_resource.jellyfin, port 443).
# En LAN, https://media.sylvain.cloud:8443 (443 est pris par le nginx d'UGOS).
# La Bbox ne filtre pas les réponses DNS en IP privée (vérifié par Sylvain).
resource "ovh_domain_zone_record" "media" {
  zone      = "sylvain.cloud"
  subdomain = "media"
  fieldtype = "A"
  ttl       = 300
  target    = "192.168.1.137"
}
