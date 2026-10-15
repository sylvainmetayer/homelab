# Deux utilisateurs S3 sur le même bucket :
# - writer : sur le poste (unités systemd du rôle keepass_backup). Il écrit et
#   lit, et ne peut supprimer que les verrous restic (locks/). Un poste
#   compromis ne peut donc pas effacer les sauvegardes.
# - admin : jamais sur disque, gardé dans KeePassXC. Sert une fois par an au
#   `restic forget --prune` et aux restaurations manuelles.
locals {
  bucket_arn  = "arn:aws:s3:::${ovh_cloud_project_storage.keepass_backup.name}"
  objects_arn = "arn:aws:s3:::${ovh_cloud_project_storage.keepass_backup.name}/*"
  locks_arn   = "arn:aws:s3:::${ovh_cloud_project_storage.keepass_backup.name}/locks/*"
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
      "Action" : concat(local.read_write_actions, ["s3:DeleteObject"]),
      "Resource" : [local.bucket_arn, local.objects_arn],
    }]
  })
}
