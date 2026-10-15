data "sops_file" "secrets" {
  source_file = "${path.root}/../../secrets.sops.yaml"
}

locals {
  ovh_service_name = data.sops_file.secrets.data["OVH_CLOUD_PROJECT_ID"]
}
