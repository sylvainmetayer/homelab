output "newt_lxc_ip" {
  description = "Newt LXC IP address"
  value       = proxmox_virtual_environment_container.newt.ipv4
}

output "debian_13_ip_address" {
  description = "Adresse IP de la VM Docker"
  value       = proxmox_virtual_environment_vm.docker.ipv4_addresses
}

output "app_lxc_ips" {
  description = "Adresse IPv4 des LXC applicatifs par role"
  value = {
    for role, container in proxmox_virtual_environment_container.apps :
    role => container.ipv4
  }
}

output "app_lxc_passwords" {
  description = "Mot de passe root initial des LXC applicatifs par role"
  sensitive   = true
  value = {
    for role, pwd in random_password.app_lxc_password :
    role => pwd.result
  }
}

# user = root
output "lxc_password" {
  value     = random_password.newt_password.result
  sensitive = true
}
