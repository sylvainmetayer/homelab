# IP publique de Pangolin, cible de l'apex sylvain.dev (redirection Traefik vers www).
data "terraform_remote_state" "pangolin" {
  backend = "s3"
  config = {
    endpoints = {
      s3 = "https://s3.eu-west-par.io.cloud.ovh.net"
    }
    bucket                      = "homelab-tf-state-sylvain"
    key                         = "homelab/pangolin.tfstate"
    region                      = "eu-west-par"
    skip_region_validation      = true
    skip_credentials_validation = true
    use_path_style              = true
  }
}

locals {
  pangolin_ip = data.terraform_remote_state.pangolin.outputs.pangolin_ip
}
