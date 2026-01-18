resource "ovh_domain_zone_record" "pangolin" {
  zone      = "sylvain.cloud"
  subdomain = "pangolin"
  fieldtype = "A"
  ttl       = 300
  target    = hcloud_server.pangolin.ipv4_address
}

resource "ovh_domain_zone_record" "sylvain_cloud" {
  zone      = "sylvain.cloud"
  subdomain = "*"
  fieldtype = "A"
  ttl       = 300
  target    = hcloud_server.pangolin.ipv4_address
}

resource "ovh_domain_zone_record" "sylvain_dev" {
  zone      = "sylvain.dev"
  subdomain = "*"
  fieldtype = "A"
  ttl       = 300
  target    = hcloud_server.pangolin.ipv4_address
}

moved {
  from = ovh_domain_zone_record.test
  to = ovh_domain_zone_record.sylvain_cloud
}
