# locals {
#   email_redirect = {
#    autodiscover = "infomaniak.com",
#    autoconfig = "infomaniak.com"
#   }
# }

# resource "ovh_domain_zone_redirection" "email" {
#   for_each = local.email_redirect
#   zone      = "sylvainmetayer.fr"
#   subdomain = each.key
#   type      = "visiblePermanent"
#   target    = each.value
# }
