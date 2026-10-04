variable "s3_endpoint" {
  description = "Endpoint S3"
  type        = string
  default     = "https://s3.eu-west-par.io.cloud.ovh.net"
}

# false tant que l'apex sylvain.dev est servi par Netlify : passer à true une
# fois ses anciens enregistrements A/AAAA supprimés chez OVH (tofu/site/README.md).
variable "sylvain_dev_apex_to_pangolin" {
  description = "Faire pointer l'apex sylvain.dev vers Pangolin (redirection 301 vers www)"
  type        = bool
  default     = false
}
