# CI deploy key: authorized on hosts the same way as keys/perso.pub etc
# (ansible/00-setup.yaml --tags setup pushes every keys/*.pub to the
# "sylvain" user's authorized_keys). Regenerating this resource rotates the
# key on the next apply; re-run 00-setup.yaml against affected hosts after.
resource "tls_private_key" "ci_deploy" {
  algorithm = "ED25519"
}

resource "local_file" "ci_deploy_public_key" {
  content         = "${trimspace(tls_private_key.ci_deploy.public_key_openssh)} github-actions\n"
  filename        = "${path.root}/../../keys/github-actions.pub"
  file_permission = "0644"
}
