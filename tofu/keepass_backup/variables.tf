variable "bucket_name" {
  description = "Bucket S3 OVH qui reçoit le dépôt restic des bases KeePass (rôle Ansible keepass_backup des dotfiles)"
  type        = string
  default     = "keepass-backup-sylvain"
}

variable "region_name" {
  description = "Région OVH Object Storage. EU-WEST-PAR est la seule région 3-AZ : le bucket est répliqué sur 3 zones."
  type        = string
  default     = "EU-WEST-PAR"
}

variable "object_lock_period" {
  description = "Rétention Object Lock par défaut (durée ISO 8601). Au-delà de la période de détection d'un incident (test de restauration mensuel)."
  type        = string
  default     = "P30D"
}

variable "noncurrent_days" {
  description = "Jours avant l'expiration d'une version non courante (hors locks/). Plus long que object_lock_period et que l'intervalle du test de restauration."
  type        = number
  default     = 120
}

# TF_VAR_state_encryption_passphrase : clé du secrets.sops.yaml racine, que
# mise charge dans l'environnement. Les tests en donnent une factice.
variable "state_encryption_passphrase" {
  description = "Passphrase PBKDF2 du chiffrement du state (la même que tofu/pangolin, tofu/github et tofu/s3_state)"
  type        = string
  sensitive   = true
}
