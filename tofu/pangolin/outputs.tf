output "pangolin_ip" {
  description = "Pangolin public IP"
  value       = hcloud_server.pangolin.ipv4_address
}
