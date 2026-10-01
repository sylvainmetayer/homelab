# Realm Keycloak du banc demo-planning-kc (planning-equipes#72).
#
# Le realm est décrit par terraform/keycloak du dépôt applicatif ; ce dossier ne
# fait que l'instancier avec un état distant. Le module porte son propre bloc
# provider (url = var.keycloak_url) : l'identifiant d'administration vient de
# KEYCLOAK_USER / KEYCLOAK_PASSWORD, le bootstrap admin du conteneur Keycloak.
#
# Les trois secrets de client sont tirés ici, et vivent donc dans l'état (le
# module les porte déjà en clair dans le sien). flip.yml les attend dans sops :
# `tofu output -raw` pour la phase 2.
#
# Temporaire : à supprimer avec le banc une fois la #72 mergée (skill remove-app).

resource "random_password" "client" {
  for_each = toset(["app", "provisioning", "mcp"])

  length  = 48
  special = false
}

module "realm" {
  source = "git::https://github.com/sylvainmetayer/planning-equipes.git//terraform/keycloak?ref=aa64656d26a837fb180db027c2056e8e169999e4"

  keycloak_url        = "https://demo-planning-kc.sylvain.dev/auth"
  planning_public_url = "https://demo-planning-kc.sylvain.dev"

  client_app_secret          = random_password.client["app"].result
  client_provisioning_secret = random_password.client["provisioning"].result
  client_mcp_secret          = random_password.client["mcp"].result

  # Mailpit du banc, joint par Keycloak sur le réseau interne de l'instance ;
  # les messages se lisent sur /mail.
  smtp = {
    host     = "demo-planning-kc-mailpit"
    port     = 1025
    from     = "noreply@demo-planning-kc.sylvain.dev"
    starttls = false
  }
}
