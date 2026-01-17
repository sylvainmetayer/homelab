data "sops_file" "secrets" {
  source_file = "${path.root}/../../secrets.sops.yaml"
}

locals {
  uptimekuma_endpoint = data.sops_file.secrets.data["UPTIMEKUMA_ENDPOINT"]
}
