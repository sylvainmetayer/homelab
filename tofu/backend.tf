terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://nbg1.your-objectstorage.com"
    }
    bucket                      = "homelab-state"
    key                         = "homelab/hetzner-vm.tfstate"
    region                      = "nbg1"
    skip_credentials_validation = false
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}
