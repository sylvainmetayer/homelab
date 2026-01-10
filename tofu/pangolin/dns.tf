resource "ovh_domain_zone_record" "pangolin" {
  zone      = "sylvain.cloud"
  subdomain = "pangolin"
  fieldtype = "A"
  ttl       = 300
  target    = hcloud_server.pangolin.ipv4_address
}

resource "ovh_domain_zone_record" "test" {
  zone      = "sylvain.cloud"
  subdomain = "test"
  fieldtype = "A"
  ttl       = 300
  target    = hcloud_server.pangolin.ipv4_address
}
