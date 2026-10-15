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
