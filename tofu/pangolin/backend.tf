terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://nbg1.your-objectstorage.com"
    }
    bucket                      = "homelab-state"
    key                         = "homelab/pangolin.tfstate"
    region                      = "nbg1"
    skip_region_validation      = true
    skip_credentials_validation = true
    use_path_style              = true
  }
}
