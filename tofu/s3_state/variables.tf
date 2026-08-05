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
