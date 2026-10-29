# Secret of the `notify` job of .github/workflows/trivy.yaml, which publishes
# the weekly scan's fixable CRITICAL vulnerabilities to ntfy.
#
# Its own environment, readable from main only: a job runs with every secret
# of its environment, and this one needs nothing but the ntfy token of the
# `github` producer (ansible/secrets.sops.yaml `ntfy_github_token`, write
# only on the `github` topic, role ntfy), the one every CI publisher uses, as
# renovate_digest_secrets.tf does: never the hosts' `scripts` token. A token
# leaked from here can only publish to that topic.
resource "github_repository_environment" "trivy_ntfy" {
  repository  = var.github_repository
  environment = "trivy-ntfy"

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "trivy_ntfy_main" {
  repository     = var.github_repository
  environment    = github_repository_environment.trivy_ntfy.environment
  branch_pattern = "main"
}

resource "github_actions_environment_secret" "trivy_ntfy_token" {
  repository  = var.github_repository
  environment = github_repository_environment.trivy_ntfy.environment
  secret_name = "TRIVY_NTFY_TOKEN"
  value       = data.sops_file.secrets.data["ntfy_github_token"]
}
