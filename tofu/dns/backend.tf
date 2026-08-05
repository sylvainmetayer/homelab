terraform {
  backend "s3" {
    endpoints                   = { s3 = "https://s3.eu-west-par.io.cloud.ovh.net" }
    bucket                      = "homelab-tf-state-sylvain"
    key                         = "dns/terraform.tfstate"
    region                      = "eu-west-par"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}
