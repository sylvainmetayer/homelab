output "bucket_name" {
  description = "Nom du bucket S3 OVH du dépôt restic"
  value       = ovh_cloud_project_storage.keepass_backup.name
}

output "restic_repository" {
  description = "Valeur de RESTIC_REPOSITORY pour le rôle keepass_backup (host_vars sops: keepass_backup_restic.repository)"
  value       = "s3:https://s3.eu-west-par.io.cloud.ovh.net/${ovh_cloud_project_storage.keepass_backup.name}"
}

output "writer_access_key" {
  description = "Access key S3 de l'utilisateur writer (poste)"
  value       = ovh_cloud_project_user_s3_credential.writer.access_key_id
}

output "writer_secret_key" {
  description = "Secret key S3 de l'utilisateur writer (poste)"
  value       = ovh_cloud_project_user_s3_credential.writer.secret_access_key
  sensitive   = true
}

output "admin_access_key" {
  description = "Access key S3 de l'utilisateur admin (KeePassXC uniquement)"
  value       = ovh_cloud_project_user_s3_credential.admin.access_key_id
}

output "admin_secret_key" {
  description = "Secret key S3 de l'utilisateur admin (KeePassXC uniquement)"
  value       = ovh_cloud_project_user_s3_credential.admin.secret_access_key
  sensitive   = true
}
