variable "bucket_name" {
  description = "Nom du bucket S3 OVH utilisé comme backend de state Terraform/OpenTofu"
  type        = string
  default     = "homelab-tf-state-sylvain"
}

variable "region_name" {
  description = "Région OVH Object Storage. Doit être une région 3-AZ (ex: EU-WEST-PAR) pour que le bucket soit répliqué sur 3 zones de disponibilité ; les régions classiques (GRA, SBG, DE, UK...) ne sont que sur 1 AZ."
  type        = string
  default     = "EU-WEST-PAR"
}

# Passphrase du chiffrement du state (encryption.tf), fournie par
# TF_VAR_state_encryption_passphrase : clé de secrets/secrets.sops.yaml, que
# mise charge dans l'environnement. Les tests en donnent une factice.
variable "state_encryption_passphrase" {
  description = "Passphrase PBKDF2 du chiffrement des states tofu/pangolin, tofu/github et tofu/s3_state"
  type        = string
  sensitive   = true
}
