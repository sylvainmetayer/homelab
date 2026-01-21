data "terraform_remote_state" "pangolin" {
  backend = "s3"
  config = {
    endpoints = {
      s3 = var.s3_endpoint
    }
    bucket                      = "homelab-state"
    key                         = "homelab/pangolin.tfstate"
    region                      = "nbg1"
    skip_region_validation      = true
    skip_credentials_validation = true
    use_path_style              = true
  }
}

locals {
  pangolin_ip = try(data.terraform_remote_state.pangolin.outputs.pangolin_ip, null)
}
