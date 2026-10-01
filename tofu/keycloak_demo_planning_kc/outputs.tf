output "oidc_client_secret" {
  description = "Valeur de demo_planning_kc_oidc_client_secret dans ansible/secrets.sops.yaml."
  value       = module.realm.oidc_client_secret
  sensitive   = true
}

output "oidc_provisioning_client_secret" {
  description = "Valeur de demo_planning_kc_oidc_provisioning_client_secret dans ansible/secrets.sops.yaml."
  value       = module.realm.oidc_provisioning_client_secret
  sensitive   = true
}

output "reste_a_faire" {
  value = module.realm.reste_a_faire
}
