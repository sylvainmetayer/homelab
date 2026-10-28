# Secret of .github/workflows/secrets-rotation.yaml, the weekly check of the
# SOPS secrets' rotation due dates (secrets-rotation.yaml).
#
# Its own environment, readable from main only: a job runs with every secret
# of its environment, and this one needs nothing but the push URL of the
# `Rotation des secrets` monitor of tofu/pangolin_config. No age key: the
# SOPS key names it reads are plaintext.
resource "github_repository_environment" "secrets_rotation" {
  repository  = var.github_repository
  environment = "secrets-rotation"

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "secrets_rotation_main" {
  repository     = var.github_repository
  environment    = github_repository_environment.secrets_rotation.environment
  branch_pattern = "main"
}

resource "github_actions_environment_secret" "secrets_rotation_push_url" {
  repository  = var.github_repository
  environment = github_repository_environment.secrets_rotation.environment
  secret_name = "SECRETS_ROTATION_PUSH_URL"
  value       = data.terraform_remote_state.pangolin_config.outputs.uptime_secrets_rotation_url
}
