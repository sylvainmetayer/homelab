data "sops_file" "secrets" {
  source_file = "${path.root}/../../secrets/secrets.sops.yaml"
}

locals {
  pangolin_password = data.sops_file.secrets.data["pangolin_password"]
}
