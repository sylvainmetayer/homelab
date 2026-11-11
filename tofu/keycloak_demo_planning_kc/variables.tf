variable "keycloak_admin_user" {
  description = "Compte d'administration du realm master : flip_planning_keycloak_admin_user du rôle Ansible (KC_BOOTSTRAP_ADMIN_USERNAME)."
  type        = string
  default     = "admin"
}

# Passphrase du chiffrement du state (encryption.tf), fournie par
# TF_VAR_state_encryption_passphrase : clé de secrets/secrets.sops.yaml, que
# mise charge dans l'environnement. Les tests en donnent une factice.
variable "state_encryption_passphrase" {
  description = "Passphrase PBKDF2 du chiffrement du state de ce module"
  type        = string
  sensitive   = true
}
