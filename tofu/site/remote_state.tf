# Outputs of tofu/pangolin_config (state being encrypted with its own passphrase,
# see encryption.tf; Ansible reads it with tofu output): the Pangolin access token
# of the OPML export (website_rss.tf).
# try() in secrets.tf: absent, the FRESHRSS_* variables are just left out.
data "terraform_remote_state" "pangolin_config" {
  backend = "s3"
  config = {
    endpoints = {
      s3 = "https://s3.eu-west-par.io.cloud.ovh.net"
    }
    bucket                      = "homelab-tf-state-sylvain"
    key                         = "homelab/pangolin_config.tfstate"
    region                      = "eu-west-par"
    skip_region_validation      = true
    skip_credentials_validation = true
    use_path_style              = true
  }
}
