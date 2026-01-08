resource "hcloud_network" "main" {
  name     = "private-network"
  ip_range = "10.0.0.0/16"
  labels = var.labels
}

resource "hcloud_network_subnet" "main" {
  network_id   = hcloud_network.main.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = "10.0.1.0/24"
}
