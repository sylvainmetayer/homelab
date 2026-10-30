variable "s3_endpoint" {
  description = "Endpoint S3"
  type        = string
  default     = "https://s3.eu-west-par.io.cloud.ovh.net"
}

# Bascule faite (tofu/site/README.md, étape 5) : l'apex pointe vers Pangolin.
# Repasser à false supprimerait l'enregistrement A et couperait sylvain.dev.
variable "sylvain_dev_apex_to_pangolin" {
  description = "Faire pointer l'apex sylvain.dev vers Pangolin (redirection 301 vers www)"
  type        = bool
  default     = true
}

# Passphrase du chiffrement du state (encryption.tf), fournie par
# TF_VAR_state_encryption_passphrase : clé de secrets/secrets.sops.yaml, que
# mise charge dans l'environnement. Les tests en donnent une factice.
variable "state_encryption_passphrase" {
  description = "Passphrase PBKDF2 du chiffrement des states tofu/pangolin (lu par terraform_remote_state)"
  type        = string
  sensitive   = true
}

# MX nul de sylvain.cloud (mail.tf), à n'activer qu'une fois vérifié que
# l'API OVH accepte la cible « 0 . » (docs/runbooks/dmarc.md).
variable "sylvain_cloud_null_mx" {
  description = "Remplacer les MX OVH de sylvain.cloud par un MX nul (RFC 7505)"
  type        = bool
  default     = false
}

# Destinataire des rapports DMARC agrégés (rua) et TLS-RPT de toutes les zones
# (mail.tf). Un alias de la boîte Infomaniak, à créer dans le Manager avant
# l'apply : une adresse inexistante fait rebondir chaque rapport.
variable "dmarc_report_address" {
  description = "Adresse qui reçoit les rapports DMARC (rua) et TLS-RPT des zones"
  type        = string
  default     = "dmarc@sylvainmetayer.fr"

  validation {
    condition     = can(regex("^[^@\\s;,!]+@[a-z0-9.-]+\\.[a-z]+$", var.dmarc_report_address))
    error_message = "dmarc_report_address doit être une adresse e-mail simple (pas de ; , ou ! : ils ont un sens dans un rua)."
  }
}
