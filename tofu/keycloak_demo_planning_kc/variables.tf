variable "keycloak_admin_user" {
  description = "Compte d'administration du realm master : flip_planning_keycloak_admin_user du rôle Ansible (KC_BOOTSTRAP_ADMIN_USERNAME)."
  type        = string
  default     = "admin"
}
