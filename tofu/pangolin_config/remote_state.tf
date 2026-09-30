# Outputs of tofu/pangolin (the Hetzner VMs), for what this configuration
# points at on the private network. No try(): tofu/pangolin is applied first,
# and a missing address must fail the plan rather than point a resource at
# nothing.
data "terraform_remote_state" "pangolin" {
  backend = "s3"
  config = {
    endpoints = {
      s3 = var.s3_endpoint
    }
    bucket                      = "homelab-tf-state-sylvain"
    key                         = "homelab/pangolin.tfstate"
    region                      = "eu-west-par"
    skip_region_validation      = true
    skip_credentials_validation = true
    use_path_style              = true
  }
}
