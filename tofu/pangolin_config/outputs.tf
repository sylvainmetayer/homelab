# output "node_proxmox_lxc_newt_id" {
#   value = pangolin_site.proxmox_lxc.newt_id
# }

# output "node_proxmox_lxc_newt_secret" {
#   value     = pangolin_site.proxmox_lxc.newt_secret
#   sensitive = true
# }

output "uptime_restore_test_urls" {
  description = "URLs push des tests de restauration (1er et 15 du mois), par entrée de local.websites (secret Actions RESTORE_TEST_PUSH_URLS, via tofu/github)"
  value       = local.restore_test_push_urls
  sensitive   = true
}
