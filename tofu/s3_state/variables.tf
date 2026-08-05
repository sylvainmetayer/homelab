variable "ovh_service_name" {
  description = "ID du projet Public Cloud OVH (Object Storage)"
  type        = string
}

variable "bucket_name" {
  description = "Nom du bucket S3 OVH utilisé comme backend de state Terraform/OpenTofu"
  type        = string
  default     = "homelab-tf-state-sylvain"
}

variable "region_name" {
  description = "Région OVH Object Storage (ex: GRA, SBG, DE, UK)"
  type        = string
  default     = "GRA"
}
