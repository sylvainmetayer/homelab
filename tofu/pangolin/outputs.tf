output "pangolin_ip" {
  description = "Pangolin public IP"
  value       = hcloud_server.pangolin.ipv4_address
}

output "s3_bucket_name" {
  description = "Nom du bucket S3 Hetzner"
  value       = aws_s3_bucket.backup.id
}

output "s3_bucket_arn" {
  description = "ARN du bucket S3 Hetzner"
  value       = aws_s3_bucket.backup.arn
}
