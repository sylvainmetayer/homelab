output "server_ip" {
  description = "Adresse IPv4 publique du serveur"
  value       = hcloud_server.pangolin.ipv4_address
}

output "network_ip" {
  description = "Adresse IP privée dans le réseau"
  value       = hcloud_server.pangolin.network[*].ip
}
