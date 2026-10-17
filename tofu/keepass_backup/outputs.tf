output "bucket_name" {
  description = "Nom du bucket S3 OVH du dépôt restic"
  value       = ovh_cloud_project_storage.keepass_backup.name
}

output "restic_repository" {
  description = "Valeur de RESTIC_REPOSITORY pour le rôle keepass_backup (host_vars sops: keepass_backup_restic.repository)"
  value       = "s3:https://s3.${lower(var.region_name)}.io.cloud.ovh.net/${ovh_cloud_project_storage.keepass_backup.name}"
}

output "bucket_owner_id" {
  description = "Propriétaire du bucket : doit n'être ni le writer ni l'admin (vérifié par le check owner_is_not_a_backup_user)"
  value       = ovh_cloud_project_storage.keepass_backup.owner_id
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

# Le refus implicite OVH ne s'applique pas au propriétaire du bucket : si l'un
# des deux utilisateurs l'était, ses restrictions ne vaudraient plus rien.
check "owner_is_not_a_backup_user" {
  assert {
    condition = !contains(
      [ovh_cloud_project_user.writer.id, ovh_cloud_project_user.admin.id],
      # owner_id est un nombre, les id d'utilisateur des chaînes : sans
      # tostring, contains() ne trouverait jamais rien.
      tostring(ovh_cloud_project_storage.keepass_backup.owner_id)
    )
    error_message = "Le propriétaire du bucket est le writer ou l'admin : le Deny explicite reste en place, mais vérifie la console OVH."
  }
}
