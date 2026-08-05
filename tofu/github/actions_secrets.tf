resource "github_actions_secret" "sops_age_key" {
  repository  = var.github_repository
  secret_name = "SOPS_AGE_KEY"
  value       = local.sops_age_key
}

resource "github_actions_secret" "ssh_private_key" {
  repository  = var.github_repository
  secret_name = "SSH_PRIVATE_KEY"
  value       = tls_private_key.ci_deploy.private_key_openssh
}
