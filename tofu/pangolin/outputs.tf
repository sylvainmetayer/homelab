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

output "storage_box_hostname" {
  description = "Hostname du Storage Box Hetzner"
  value       = hcloud_storage_box.backups.server
}

output "storage_box_username" {
  description = "Nom d'utilisateur SSH pour la Storage Box"
  value       = hcloud_storage_box.backups.username
}

output "storage_box_id" {
  description = "ID du Storage Box Hetzner"
  value       = hcloud_storage_box.backups.id
}

output "storage_box_password" {
  description = "Mot de passe du Storage Box Hetzner"
  value       = random_password.storage_box_password.result
  sensitive = true
}

output "storage_box_ssh_private_key" {
  description = "Clé privée SSH pour accéder à la Storage Box Hetzner"
  value       = tls_private_key.storage_box.private_key_pem
  sensitive = true
}

output "storage_box_ssh_public_key" {
  description = "Clé publique SSH pour accéder à la Storage Box Hetzner"
  value       = tls_private_key.storage_box.public_key_openssh
}
