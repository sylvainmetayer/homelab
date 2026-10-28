# Secret of .github/workflows/renovate-digest.yaml, the weekly Renovate
# digest published to ntfy.
#
# Its own environment, readable from main only: a job runs with every secret
# of its environment, and this one needs nothing but the write-only token of
# the ntfy publisher `github` (role ntfy, ntfy_publishers), the key
# ntfy_github_token of ansible/secrets.sops.yaml. Its own publisher, not the
# hosts' `scripts`: a token leaked from a CI job can only write to the github
# topic, and rotating it touches neither docker, pi nor flip. The GitHub API
# is read with the job's own GITHUB_TOKEN (permissions of the workflow).
resource "github_repository_environment" "renovate_digest" {
  repository  = var.github_repository
  environment = "renovate-digest"

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "renovate_digest_main" {
  repository     = var.github_repository
  environment    = github_repository_environment.renovate_digest.environment
  branch_pattern = "main"
}

resource "github_actions_environment_secret" "renovate_digest_ntfy_token" {
  repository  = var.github_repository
  environment = github_repository_environment.renovate_digest.environment
  secret_name = "RENOVATE_DIGEST_NTFY_TOKEN"
  value       = data.sops_file.secrets.data["ntfy_github_token"]
}
