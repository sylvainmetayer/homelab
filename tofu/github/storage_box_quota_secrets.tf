# Secrets of .github/workflows/storage-box-quota.yaml, the weekly check of the
# backup Storage Box's usage against its quota.
#
# Their own environment, readable from main only: a job runs with every
# secret of its environment, and this one needs neither the age key nor the
# deploy key, nor the restore test's Storage Box key. It gets:
#   - a Hetzner Console API token of the project, **Read** permission only,
#     created by hand (Console → Security → API tokens: the provider cannot
#     create one) and stored in ansible/secrets.sops.yaml as
#     `hcloud_readonly_token`. Never tofu/pangolin's HCLOUD_TOKEN, which is
#     read-write: in a CI job it could delete the Storage Box and Pangolin;
#   - the push URL of the `Storage Box` monitor of tofu/pangolin_config.
resource "github_repository_environment" "storage_box_quota" {
  repository  = var.github_repository
  environment = "storage-box-quota"

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "storage_box_quota_main" {
  repository     = var.github_repository
  environment    = github_repository_environment.storage_box_quota.environment
  branch_pattern = "main"
}

resource "github_actions_environment_secret" "storage_box_quota_hcloud_token" {
  repository  = var.github_repository
  environment = github_repository_environment.storage_box_quota.environment
  secret_name = "STORAGE_BOX_QUOTA_HCLOUD_TOKEN"
  value       = data.sops_file.secrets.data["hcloud_readonly_token"]
}

resource "github_actions_environment_secret" "storage_box_quota_push_url" {
  repository  = var.github_repository
  environment = github_repository_environment.storage_box_quota.environment
  secret_name = "STORAGE_BOX_QUOTA_PUSH_URL"
  value       = data.terraform_remote_state.pangolin_config.outputs.uptime_storage_box_quota_url
}
