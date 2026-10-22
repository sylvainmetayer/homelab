# Secrets of .github/workflows/restore-test.yaml, the restore test of the
# borg repositories on the 1st and the 15th (issue #444).
#
# The Storage Box access is the read-only sub-account of tofu/pangolin
# (storage_box.tf), never the main account's key, which can delete every
# repository. The push URLs are the `Restore test <app>` monitors of
# tofu/pangolin_config, one map for the whole matrix.
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

resource "github_actions_secret" "restore_test_ssh_key" {
  repository  = var.github_repository
  secret_name = "RESTORE_TEST_SSH_KEY"
  value       = data.terraform_remote_state.pangolin.outputs.storage_box_restore_test_ssh_private_key
}

# user@host, the prefix of every repository URL the workflow builds.
resource "github_actions_secret" "restore_test_storage_box" {
  repository  = var.github_repository
  secret_name = "RESTORE_TEST_STORAGE_BOX"
  value       = "${data.terraform_remote_state.pangolin.outputs.storage_box_restore_test_username}@${data.terraform_remote_state.pangolin.outputs.storage_box_restore_test_server}"
}

resource "github_actions_secret" "restore_test_push_urls" {
  repository  = var.github_repository
  secret_name = "RESTORE_TEST_PUSH_URLS"
  value       = jsonencode(data.terraform_remote_state.pangolin_config.outputs.uptime_restore_test_urls)
}
