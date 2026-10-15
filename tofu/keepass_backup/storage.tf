# Bucket S3 OVH dédié au dépôt restic des bases KeePass (rôle dotfiles
# keepass_backup).
#
# Object Lock en mode GOVERNANCE avec une rétention par défaut : aucune version
# d'objet ne peut être détruite avant l'échéance, même avec une clé compromise.
# Les suppressions de restic (verrous, prune annuel) restent possibles : sans
# versionId, elles ne posent qu'un delete marker. Object Lock ne s'active qu'à
# la création du bucket et active de lui-même le versioning.
resource "ovh_cloud_project_storage" "keepass_backup" {
  service_name = local.ovh_service_name
  region_name  = var.region_name
  name         = var.bucket_name

  versioning = {
    status = "enabled"
  }

  object_lock = {
    status = "enabled"
    rule = {
      mode   = "governance"
      period = var.object_lock_period
    }
  }

  # SSE-OMK : chiffrement au repos côté OVH, en plus du chiffrement restic.
  encryption = {
    sse_algorithm = "AES256"
  }
}

# Sans cycle de vie, le versioning garderait tout pour toujours : chaque verrou
# restic laisse une version, et le prune annuel ne libérerait aucun espace.
# Les versions verrouillées ne peuvent pas expirer avant la fin de la rétention
# Object Lock : les durées ci-dessous s'appliquent au-delà.
resource "ovh_cloud_project_storage_object_bucket_lifecycle_configuration" "keepass_backup" {
  service_name   = local.ovh_service_name
  region_name    = var.region_name
  container_name = ovh_cloud_project_storage.keepass_backup.name

  rules = [
    {
      id     = "locks"
      status = "enabled"
      filter = {
        prefix = "locks/"
      }
      noncurrent_version_expiration = {
        noncurrent_days = 1
      }
      expiration = {
        expired_object_delete_marker = true
      }
    },
    {
      # Bien plus long que le test de restauration mensuel : un écrasement
      # malveillant est vu avant que la bonne version expire.
      id     = "noncurrent"
      status = "enabled"
      filter = {
        prefix = ""
      }
      noncurrent_version_expiration = {
        noncurrent_days = var.noncurrent_days
      }
      abort_incomplete_multipart_upload = {
        days_after_initiation = 7
      }
    },
  ]
}
