# Les secrets que le rôle Ansible pose dans les conteneurs, lus au même
# endroit : ils ne peuvent pas diverger.
#   - prod_planning_keycloak_admin_password : KC_BOOTSTRAP_ADMIN_PASSWORD ;
#   - prod_planning_oidc_client_secret : OIDC_CLIENT_SECRET de l'application,
#     et le secret du client planning-app ici (≥ 32 caractères, refusé sinon).
data "sops_file" "ansible" {
  source_file = "${path.root}/../../secrets/ansible.sops.yaml"
}

locals {
  keycloak_admin_password = data.sops_file.ansible.data["prod_planning_keycloak_admin_password"]
  oidc_client_secret      = data.sops_file.ansible.data["prod_planning_oidc_client_secret"]

  # Sortie {"id": …, "token": …} de tofu/pangolin_config (websites.tf).
  pangolin_access_token = jsondecode(data.terraform_remote_state.pangolin_config.outputs.flip_planning_access_token)
  pangolin_access_headers = {
    "P-Access-Token-Id" = tostring(local.pangolin_access_token.id)
    "P-Access-Token"    = local.pangolin_access_token.token
  }
}

# Le state de tofu/pangolin_config, chiffré : encryption.tf le déchiffre.
data "terraform_remote_state" "pangolin_config" {
  backend = "s3"
  config = {
    endpoints = {
      s3 = "https://s3.eu-west-par.io.cloud.ovh.net"
    }
    bucket                      = "homelab-tf-state-sylvain"
    key                         = "homelab/pangolin_config.tfstate"
    region                      = "eu-west-par"
    skip_region_validation      = true
    skip_credentials_validation = true
    use_path_style              = true
  }
}
