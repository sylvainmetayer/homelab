# Bucket S3 OVH (Object Storage) dédié au state Terraform/OpenTofu des autres
# stacks. Volontairement séparé des autres stacks : un stack ne doit pas gérer
# le bucket qui contient son propre state.
resource "ovh_cloud_project_storage" "tf_state" {
  service_name = var.ovh_service_name
  region_name  = var.region_name
  name         = var.bucket_name

  versioning = {
    status = "enabled"
  }
}
