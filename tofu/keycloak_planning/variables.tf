variable "keycloak_url" {
  description = "Racine publique de Keycloak (KC_HOSTNAME du rôle flip_planning)."
  type        = string
  default     = "https://flip-planning.sylvain.cloud/auth"
}

variable "keycloak_admin_user" {
  description = "Compte d'administration du realm master : flip_planning_keycloak_admin_user du rôle Ansible (KC_BOOTSTRAP_ADMIN_USERNAME)."
  type        = string
  default     = "admin"
}

variable "dcr_trusted_hosts" {
  description = <<-EOT
    Hôtes sur lesquels un client MCP enregistré dynamiquement (anonyme) peut
    déclarer ses URI de redirection : Claude (web) et Le Chat. Vide :
    enregistrement fermé (défaut de Keycloak). README.md, « Enregistrement
    dynamique ».
  EOT
  type        = list(string)
  default     = ["claude.ai", "claude.com", "chat.mistral.ai"]

  validation {
    condition     = alltrue([for host in var.dcr_trusted_hosts : can(regex("^[a-z0-9.-]+$", host)) && !startswith(host, "*")])
    error_message = "Des noms d'hôte nus, sans schéma, sans chemin ni joker."
  }
}

# Passphrase du chiffrement du state (encryption.tf), fournie par
# TF_VAR_state_encryption_passphrase : clé de secrets/secrets.sops.yaml, que
# mise charge dans l'environnement. Les tests en donnent une factice.
variable "state_encryption_passphrase" {
  description = "Passphrase PBKDF2 du chiffrement du state de ce module"
  type        = string
  sensitive   = true
}

# Passphrase DÉDIÉE du state de tofu/pangolin_config, lu par
# terraform_remote_state (encryption.tf) : TF_VAR_pangolin_config_state_passphrase,
# clé de secrets/secrets.sops.yaml que mise charge. Tests : valeur factice.
variable "pangolin_config_state_passphrase" {
  description = "Passphrase PBKDF2 du chiffrement du state de tofu/pangolin_config (lu par terraform_remote_state)"
  type        = string
  sensitive   = true
}
