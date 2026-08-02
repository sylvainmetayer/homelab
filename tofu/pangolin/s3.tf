# Bucket S3 Hetzner pour le homelab
resource "aws_s3_bucket" "backup" {
  bucket = var.s3_bucket_name
}
resource "aws_s3_bucket_versioning" "backup_versioning" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Suspended"
  }
}

# Bucket S3 OVH (Object Storage) pour le homelab
resource "aws_s3_bucket" "ovh_backup" {
  provider = aws.ovh_s3
  bucket   = var.ovh_s3_bucket_name
}
resource "aws_s3_bucket_versioning" "ovh_backup_versioning" {
  provider = aws.ovh_s3
  bucket   = aws_s3_bucket.ovh_backup.id

  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Suspended"
  }
}
