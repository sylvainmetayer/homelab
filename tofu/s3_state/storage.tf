# Bucket S3 OVH (Object Storage) dédié au state Terraform/OpenTofu de tous les
# stacks, y compris celui de ce module (backend.tf : homelab/s3_state.tfstate,
# dans ce même bucket). Un remplacement du bucket (nom de variable changé,
# évolution du provider) emporterait donc tous les states, celui qui sert à le
# recréer compris : prevent_destroy le refuse au plan. Les states chiffrés ne
# se refont que par imports.
resource "ovh_cloud_project_storage" "tf_state" {
  service_name = local.ovh_service_name
  region_name  = var.region_name
  name         = var.bucket_name

  versioning = {
    status = "enabled"
  }

  # SSE-OMK (Server-Side Encryption, clés gérées par OVHcloud) : chiffrement
  # au repos des objets du bucket, transparent côté client.
  encryption = {
    sse_algorithm = "AES256"
  }

  lifecycle {
    prevent_destroy = true
  }
}
