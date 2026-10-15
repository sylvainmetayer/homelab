# Deux utilisateurs S3 sur le même bucket :
# - writer : sur le poste (unités systemd du rôle keepass_backup). Il écrit et
#   lit, et ne peut supprimer que les verrous restic (locks/). Il ne lance ni
#   forget ni prune : la rétention se fait une fois par an avec la clé admin.
# - admin : jamais sur disque, gardé dans KeePassXC. Sert au
#   `restic forget --prune` annuel et aux restaurations depuis les versions.
locals {
  bucket_arn  = "arn:aws:s3:::${ovh_cloud_project_storage.keepass_backup.name}"
  objects_arn = "arn:aws:s3:::${ovh_cloud_project_storage.keepass_backup.name}/*"
  locks_arn   = "arn:aws:s3:::${ovh_cloud_project_storage.keepass_backup.name}/locks/*"
  # Tout ce qui n'est pas un verrou dans un dépôt restic.
  repository_data_arns = [
    "arn:aws:s3:::${ovh_cloud_project_storage.keepass_backup.name}/config",
    "arn:aws:s3:::${ovh_cloud_project_storage.keepass_backup.name}/keys/*",
    "arn:aws:s3:::${ovh_cloud_project_storage.keepass_backup.name}/data/*",
    "arn:aws:s3:::${ovh_cloud_project_storage.keepass_backup.name}/index/*",
    "arn:aws:s3:::${ovh_cloud_project_storage.keepass_backup.name}/snapshots/*",
  ]
  read_write_actions = [
    "s3:GetObject",
    "s3:PutObject",
    "s3:ListBucket",
    "s3:GetBucketLocation",
    "s3:ListMultipartUploadParts",
    "s3:ListBucketMultipartUploads",
    "s3:AbortMultipartUpload",
  ]
}

resource "ovh_cloud_project_user" "writer" {
  service_name = local.ovh_service_name
  description  = "keepass_backup_writer"
  role_name    = "objectstore_operator"
}

resource "ovh_cloud_project_user_s3_credential" "writer" {
  service_name = local.ovh_service_name
  user_id      = ovh_cloud_project_user.writer.id
}

resource "ovh_cloud_project_user_s3_policy" "writer" {
  service_name = local.ovh_service_name
  user_id      = ovh_cloud_project_user.writer.id
  policy = jsonencode({
    "Statement" : [
      {
        "Sid" : "KeepassBackupReadWrite",
        "Effect" : "Allow",
        "Action" : local.read_write_actions,
        "Resource" : [local.bucket_arn, local.objects_arn],
      },
      {
        # restic pose un verrou à chaque opération et le retire ensuite :
        # c'est la seule suppression dont le poste a besoin.
        "Sid" : "KeepassBackupLocksOnly",
        "Effect" : "Allow",
        "Action" : ["s3:DeleteObject"],
        "Resource" : [local.locks_arn],
      },
      {
        # Refus explicite : chez OVH, le refus implicite ne s'applique pas au
        # propriétaire du bucket. Celui-ci prime même si le writer l'était.
        "Sid" : "KeepassBackupNeverDeleteData",
        "Effect" : "Deny",
        "Action" : ["s3:DeleteObject"],
        "Resource" : local.repository_data_arns,
      },
    ]
  })
}

resource "ovh_cloud_project_user" "admin" {
  service_name = local.ovh_service_name
  description  = "keepass_backup_admin"
  role_name    = "objectstore_operator"
}

resource "ovh_cloud_project_user_s3_credential" "admin" {
  service_name = local.ovh_service_name
  user_id      = ovh_cloud_project_user.admin.id
}

resource "ovh_cloud_project_user_s3_policy" "admin" {
  service_name = local.ovh_service_name
  user_id      = ovh_cloud_project_user.admin.id
  policy = jsonencode({
    "Statement" : [{
      "Sid" : "KeepassBackupAdmin",
      "Effect" : "Allow",
      # Les droits de versions permettent de restaurer un objet écrasé.
      "Action" : concat(local.read_write_actions, ["s3:DeleteObject", "s3:ListBucketVersions", "s3:GetObjectVersion"]),
      "Resource" : [local.bucket_arn, local.objects_arn],
    }]
  })
}
