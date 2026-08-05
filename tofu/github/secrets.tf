data "sops_file" "secrets" {
  # Distinct from the root-level secrets.sops.yaml (infra/Terraform secrets):
  # this one holds the app/Ansible secrets, including the github-actions
  # recipient's own AGE private key added alongside it in .sops.yaml.
  source_file = "${path.root}/../../ansible/secrets.sops.yaml"
}

locals {
  # AGE private key for the "github-actions" recipient declared in .sops.yaml,
  # used by CI to decrypt ansible/secrets.sops.yaml.
  sops_age_key = data.sops_file.secrets.data["github_actions_sops_age_key"]
}
