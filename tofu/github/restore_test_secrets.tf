# Secrets of .github/workflows/restore-test.yaml, the restore test of the
# borg repositories on the 1st and the 15th (issue #444).
#
# Their own environment, not `production`: a job runs with every secret of
# its environment, and the restore test must not be able to read the CI's
# age key (all of ansible/secrets.sops.yaml) nor its SSH deploy key. It gets
# only what it needs:
#   - the key of the read-only Storage Box sub-account of tofu/pangolin
#     (storage_box.tf), never the main account's, which can delete
#     everything, nor a host's;
#   - the borg passphrase, the same for every repository;
#   - the push URL of the `Restore test` monitor of tofu/pangolin_config.
# Readable from main only, like `production`: a PR branch sees none of them.
resource "github_repository_environment" "restore_test" {
  repository  = var.github_repository
  environment = "restore-test"

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "restore_test_main" {
  repository     = var.github_repository
  environment    = github_repository_environment.restore_test.environment
  branch_pattern = "main"
}

# tofu/pangolin's state is encrypted: encryption.tf decrypts it for this
# data source (remote_state_data_sources).
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

resource "github_actions_environment_secret" "restore_test_ssh_key" {
  repository  = var.github_repository
  environment = github_repository_environment.restore_test.environment
  secret_name = "RESTORE_TEST_SSH_KEY"
  value       = data.terraform_remote_state.pangolin.outputs.storage_box_restore_test_ssh_private_key
}

# user@host, the prefix of every repository URL the workflow builds.
resource "github_actions_environment_secret" "restore_test_storage_box" {
  repository  = var.github_repository
  environment = github_repository_environment.restore_test.environment
  secret_name = "RESTORE_TEST_STORAGE_BOX"
  value       = "${data.terraform_remote_state.pangolin.outputs.storage_box_restore_test_username}@${data.terraform_remote_state.pangolin.outputs.storage_box_restore_test_server}"
}

resource "github_actions_environment_secret" "restore_test_borg_passphrase" {
  repository  = var.github_repository
  environment = github_repository_environment.restore_test.environment
  secret_name = "RESTORE_TEST_BORG_PASSPHRASE"
  value       = data.sops_file.secrets.data["backup_passphrase"]
}

resource "github_actions_environment_secret" "restore_test_push_url" {
  repository  = var.github_repository
  environment = github_repository_environment.restore_test.environment
  secret_name = "RESTORE_TEST_PUSH_URL"
  value       = data.terraform_remote_state.pangolin_config.outputs.uptime_restore_test_url
}
