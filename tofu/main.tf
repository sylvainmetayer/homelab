locals {
  public_ips = [
    "0.0.0.0/0",
    "::/0"
  ]
}

resource "hcloud_ssh_key" "keepassxc" {
  name       = var.ssh_key_name
  public_key = file("${path.root}/../key.pub")
  labels     = var.labels
}

resource "hcloud_server" "vm" {
  name        = var.vm_name
  server_type = var.server_type
  image       = var.image
  location    = var.location

  ssh_keys = [hcloud_ssh_key.keepassxc.id]

  network {
    network_id = hcloud_network.main.id
  }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  labels = var.labels

  user_data = var.user_data
}

resource "hcloud_firewall" "vm_firewall" {
  name = "firewall"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.ssh_allowed_ips
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = local.public_ips
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = local.public_ips
  }

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = local.public_ips
  }

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = local.public_ips
  }
}

resource "hcloud_firewall_attachment" "vm_firewall" {
  firewall_id = hcloud_firewall.vm_firewall.id
  server_ids  = [hcloud_server.vm.id]
}
