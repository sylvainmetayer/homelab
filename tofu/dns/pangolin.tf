resource "ovh_domain_zone_record" "sylvain_cloud" {
  zone      = "sylvain.cloud"
  subdomain = "*"
  fieldtype = "A"
  ttl       = 300
  target    = local.pangolin_ip
}

resource "ovh_domain_zone_record" "sylvain_cloud_root" {
  zone      = "sylvain.cloud"
  subdomain = ""
  fieldtype = "A"
  ttl       = 300
  target    = local.pangolin_ip
}

resource "ovh_domain_zone_record" "sylvain_dev" {
  zone      = "sylvain.dev"
  subdomain = "*"
  fieldtype = "A"
  ttl       = 300
  target    = local.pangolin_ip
}
