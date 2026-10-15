# Bucket S3 OVH dédié au dépôt restic des bases KeePass. Le versioning garde
# les versions précédentes d'un objet écrasé ; restic n'écrase jamais rien,
# c'est une ceinture de plus contre une clé writer compromise.
resource "ovh_cloud_project_storage" "keepass_backup" {
  service_name = local.ovh_service_name
  region_name  = var.region_name
  name         = var.bucket_name

  versioning = {
    status = "enabled"
  }

  # SSE-OMK : chiffrement au repos côté OVH, en plus du chiffrement restic.
  encryption = {
    sse_algorithm = "AES256"
  }
}
