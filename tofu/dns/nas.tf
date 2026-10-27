# Interface d'UGOS (NAS) en HTTPS : https://nas.sylvain.cloud:8443, servie par
# le Traefik du NAS (ansible/roles/nas_proxy, certificat Let's Encrypt par
# DNS-01 OVH), comme media.sylvain.cloud (media.tf). Ce A vers l'IP *privée*
# du NAS prime sur le joker *.sylvain.cloud (pangolin.tf) : rien n'est exposé
# sur Internet. Dehors, le client Pangolin résout le même nom vers la
# ressource privée (alias de pangolin_site_resource.nas, site proxmox-lxc), qui
# vise la même IP. Secours : http://192.168.1.137:9999.
resource "ovh_domain_zone_record" "nas" {
  zone      = "sylvain.cloud"
  subdomain = "nas"
  fieldtype = "A"
  ttl       = 300
  target    = "192.168.1.137"
}
