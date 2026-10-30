data "sops_file" "secrets" {
  source_file = "${path.root}/../../secrets/secrets.sops.yaml"
}

locals {
  proxmox_api_token = data.sops_file.secrets.data["PROXMOX_TOKEN"]
}
