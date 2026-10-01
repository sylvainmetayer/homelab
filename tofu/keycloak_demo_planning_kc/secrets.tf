# Le secret que le rôle Ansible pose en KC_BOOTSTRAP_ADMIN_PASSWORD : lu au
# même endroit, il ne peut pas diverger de celui du conteneur.
data "sops_file" "ansible" {
  source_file = "${path.root}/../../ansible/secrets.sops.yaml"
}

locals {
  keycloak_admin_password = data.sops_file.ansible.data["demo_planning_kc_keycloak_admin_password"]
}
