data "sops_file" "secrets" {
  source_file = "${path.root}/../../secrets.sops.yaml"
}

locals {
  proxmox_api_token        = data.sops_file.secrets.data["PROXMOX_TOKEN"]
  newt_lxc_pangolin_id     = data.sops_file.secrets.data["newt_lxc_pangolin_id"]
  newt_lxc_pangolin_secret = data.sops_file.secrets.data["newt_lxc_pangolin_secret"]
}
