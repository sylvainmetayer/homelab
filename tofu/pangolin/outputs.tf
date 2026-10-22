output "pangolin_ip" {
  description = "Pangolin public IP"
  value       = hcloud_server.pangolin.ipv4_address
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
  sensitive   = true
}

output "storage_box_ssh_private_key" {
  description = "Clé privée SSH pour accéder à la Storage Box Hetzner"
  value       = tls_private_key.storage_box.private_key_pem
  sensitive   = true
}

output "storage_box_ssh_public_key" {
  description = "Clé publique SSH pour accéder à la Storage Box Hetzner"
  value       = tls_private_key.storage_box.public_key_openssh
}

output "flip_private_ip" {
  description = "IP privée du serveur Flip Planning (lue par tofu/pangolin_config pour flip.internal)"
  value       = one(hcloud_server.flip.network).ip
}

output "storage_box_restore_test_username" {
  description = "Utilisateur SSH du sous-compte en lecture seule du test de restauration (lu par tofu/github)"
  value       = hcloud_storage_box_subaccount.restore_test.username
}

output "storage_box_restore_test_server" {
  description = "Nom d'hôte du sous-compte du test de restauration (lu par tofu/github)"
  value       = hcloud_storage_box_subaccount.restore_test.server
}

output "storage_box_restore_test_ssh_private_key" {
  description = "Clé privée SSH du sous-compte du test de restauration (secret Actions, via tofu/github)"
  value       = tls_private_key.storage_box_restore_test.private_key_openssh
  sensitive   = true
}

output "storage_box_restore_test_ssh_public_key" {
  description = "Clé publique du sous-compte du test de restauration (écrite dans backup/.ssh/authorized_keys par ansible/backup.yaml)"
  value       = tls_private_key.storage_box_restore_test.public_key_openssh
}
