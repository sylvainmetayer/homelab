# Le realm Keycloak d'une instance Planning Équipes, décrit plutôt qu'installé.
# C'est la description UNIQUE du realm de production : rôles, clients, flow de
# connexion, thème, relais SMTP. docker/keycloak/realm-planning.json en est le
# pendant de développement, et TerraformKeycloakStructuralTest tient les deux
# ensemble (mêmes rôles, même arbre de connexion, PKCE des deux côtés).
#
#   terraform init
#   terraform plan
#   terraform apply
#
# Les PERSONNES n'y sont pas : ansible/keycloak-planning.yml crée et désactive
# les comptes du personnel, leur accorde leurs rôles et envoie les invitations
# — voir docs/keycloak.md § Terraform décrit le realm, Ansible les personnes.

terraform {
  # 1.9 est le plancher : la validation « un nom d'utilisateur SMTP sans mot de
  # passe n'authentifie rien » lit une AUTRE variable, ce que Terraform n'a
  # appris qu'à cette version.
  required_version = ">= 1.9"

  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = "~> 5.9"
    }
  }
}

provider "keycloak" {
  client_id = "admin-cli"
  url       = var.keycloak_url
  # Jamais en clair ici : un identifiant d'administration dans un fichier
  # versionné est un identifiant publié. Laissées à null, ces deux variables
  # laissent le fournisseur lire KEYCLOAK_USER et KEYCLOAK_PASSWORD ; une
  # configuration qui appelle ce dossier comme module (le bloc provider le
  # suit) les renseigne depuis son propre coffre.
  username = var.admin_username
  password = var.admin_password
}
