output "newt_lxc_ip" {
  description = "Newt LXC IP address"
  value       = proxmox_virtual_environment_container.newt.ipv4
}

output "debian_13_ip_address" {
  description = "Adresse IP de la VM Docker"
  value       = proxmox_virtual_environment_vm.docker.ipv4_addresses
}
