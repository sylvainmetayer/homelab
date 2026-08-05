output "ci_deploy_public_key" {
  description = "CI deploy public key (also written to keys/github-actions.pub) — authorize it on hosts via ansible/00-setup.yaml --tags setup"
  value       = tls_private_key.ci_deploy.public_key_openssh
}
