# output "proxmox_vm_ip" {
#   description = "Proxmox VM IP address"
#   value       = try(proxmox_virtual_environment_vm.debian_base[0].ipv4_addresses[1][0], "pending")
# }

output "newt_lxc_ip" {
  description = "Newt LXC IP address"
  value       = proxmox_virtual_environment_container.newt.ipv4
}
