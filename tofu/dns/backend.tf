terraform {
  backend "s3" {
    endpoints                   = { s3 = "https://nbg1.your-objectstorage.com" }
    bucket                      = "homelab-state"
    key                         = "dns/terraform.tfstate"
    region                      = "nbg1"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}
