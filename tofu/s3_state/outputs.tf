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

output "s3_access_key" {
  description = "Access key S3 OVH de l'utilisateur tf_state"
  value       = ovh_cloud_project_user_s3_credential.tf_state.access_key_id
}

output "s3_secret_key" {
  description = "Secret key S3 OVH de l'utilisateur tf_state"
  value       = ovh_cloud_project_user_s3_credential.tf_state.secret_access_key
  sensitive   = true
}
