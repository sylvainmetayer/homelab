# Ce qu'il reste à poser sur l'instance Planning Équipes. Écrit ici plutôt que
# dans la documentation parce que plusieurs de ces valeurs dépendent de ce
# code-ci, et qu'une documentation ne suit pas un `terraform apply`.
output "variables_application" {
  description = "Les variables d'environnement non secrètes de l'instance (.env.prod)."
  value = {
    OIDC_ENABLED                 = "true"
    OIDC_AUTH_SERVER_URL         = "${var.keycloak_url}/realms/${keycloak_realm.planning.realm}"
    OIDC_CLIENT_ID               = keycloak_openid_client.app.client_id
    OIDC_ANIMATEUR_ROLE          = keycloak_role.animateur.name
    OIDC_MCP_AUDIENCE            = keycloak_openid_client.mcp_resource.client_id
    OIDC_FORCE_HTTPS             = "true"
    OIDC_PROVISIONING_ENABLED    = "true"
    OIDC_PROVISIONING_SERVER_URL = var.keycloak_url
    OIDC_PROVISIONING_REALM      = keycloak_realm.planning.realm
    OIDC_PROVISIONING_CLIENT_ID  = keycloak_openid_client.provisioning.client_id
    ADMIN_SECOURS_ENABLED        = "false"
  }
}

# Les secrets sont ceux que VOUS avez fournis en entrée, pas des valeurs
# engendrées : ils sont repris ici pour qu'un `terraform output -raw …` suffise
# à remplir l'instance, sans aller les rechercher dans le coffre.
output "oidc_client_secret" {
  description = "OIDC_CLIENT_SECRET — secret du client de l'application web."
  value       = keycloak_openid_client.app.client_secret
  sensitive   = true
}

output "oidc_provisioning_client_secret" {
  description = "OIDC_PROVISIONING_CLIENT_SECRET — secret du compte de service."
  value       = keycloak_openid_client.provisioning.client_secret
  sensitive   = true
}

output "mcp_client_secret" {
  description = "Secret du client MCP automatisé, à donner aux clients scriptés."
  value       = keycloak_openid_client.mcp.client_secret
  sensitive   = true
}

# Ce que ce code NE fait pas, rappelé à chaque `apply` plutôt qu'enfoui dans un
# fichier que personne ne relit.
output "reste_a_faire" {
  description = "Ce qui n'est pas décrit ici, et par quoi le faire."
  value = [
    "Les PERSONNES du personnel (administrateurs nominatifs, rôles, invitations) : ansible/keycloak-planning.yml, après cet apply.",
    "Les comptes des animateurs : créés par l'application quand on crée leur fiche (OIDC_PROVISIONING_ENABLED=true).",
    "Le compte d'amorçage de la console : à remplacer par un compte permanent, puis à supprimer.",
    "Recette après déploiement : docs/keycloak.md § Recette.",
  ]
}
