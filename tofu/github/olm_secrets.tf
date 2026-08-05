# Reads the CI OLM client's credentials out of tofu/pangolin_config's
# state (same S3 backend, different key) instead of duplicating the
# pangolin provider/resource here. See private_resources.tf there for
# pangolin_client.ci_runner.
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

resource "github_actions_secret" "olm_id" {
  repository  = var.github_repository
  secret_name = "OLM_ID"
  value       = data.terraform_remote_state.pangolin_config.outputs.ci_olm_id
}

resource "github_actions_secret" "olm_secret" {
  repository  = var.github_repository
  secret_name = "OLM_SECRET"
  value       = data.terraform_remote_state.pangolin_config.outputs.ci_olm_secret
}
