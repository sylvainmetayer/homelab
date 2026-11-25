terraform {
  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = "~> 5.9"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.3"
    }
  }
}

# L'API d'administration (/auth/admin/…) et le realm master restent derrière le
# SSO Pangolin de Flip Planning : seuls /auth/realms/planning/* et
# /auth/resources/* en sont sortis (website_flip_planning.tf). Le provider passe
# ce mur avec le jeton d'accès de la ressource (le même que la sonde Uptime
# Kuma, sortie flip_planning_access_token de tofu/pangolin_config), puis se
# connecte avec le bootstrap admin du conteneur.
provider "keycloak" {
  client_id = "admin-cli"
  url       = var.keycloak_url
  username  = var.keycloak_admin_user
  password  = local.keycloak_admin_password

  additional_headers = local.pangolin_access_headers
}
