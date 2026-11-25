output "issuer" {
  description = "OIDC_AUTH_SERVER_URL de l'application (flip_planning_oidc_auth_server_url le dérive déjà du domaine)."
  value       = local.issuer
}
