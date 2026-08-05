output "bucket_name" {
  description = "Nom du bucket S3 OVH utilisé pour le state Terraform/OpenTofu"
  value       = ovh_cloud_project_storage.tf_state.name
}

output "bucket_region" {
  description = "Région du bucket S3 OVH"
  value       = ovh_cloud_project_storage.tf_state.region
}

output "bucket_virtual_host" {
  description = "Endpoint virtual-host du bucket S3 OVH"
  value       = ovh_cloud_project_storage.tf_state.virtual_host
}
