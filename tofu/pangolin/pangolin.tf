locals {
  public_ips = [
    "0.0.0.0/0",
    "::/0"
  ]
}

resource "hcloud_ssh_key" "keepassxc" {
  name       = var.ssh_key_name
  public_key = file("${path.root}/../../key.pub")
  labels     = var.labels
}

resource "hcloud_server" "pangolin" {
  lifecycle {
    ignore_changes  = [user_data, network]
    prevent_destroy = true
  }

  firewall_ids = [hcloud_firewall.pangolin.id]
  backups      = true
  name         = var.vm_name
  server_type  = var.server_type
  image        = var.image
  location     = var.location

  ssh_keys = [hcloud_ssh_key.keepassxc.id]

  network {
    network_id = hcloud_network.main.id
  }

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  labels = var.labels

  user_data = templatefile("${path.root}/user_data.yaml", {
    pangolin_password      = local.pangolin_password
    public_ssh_key         = file("${path.root}/../../key.pub")
    pangolin_dashboard_url = var.pangolin_config.dashboard_url
    pangolin_base_domain   = var.pangolin_config.base_domain
    pangolin_log_level     = var.pangolin_config.log_level
    pangolin_secret        = local.pangolin_secret
    smtp_user              = local.smtp_user
    smtp_pass              = local.smtp_pass
    le_email               = local.le_email
  })
}

resource "hcloud_firewall" "pangolin" {
  name = "pangolin"

  // https://docs.pangolin.net/self-host/quick-install#prerequisites
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "51820"
    source_ips = local.public_ips
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "21820"
    source_ips = local.public_ips
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = local.public_ips
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

resource "hcloud_network" "main" {
  name     = "private-network"
  ip_range = "10.0.0.0/16"
  labels   = var.labels
}

resource "hcloud_network_subnet" "main" {
  network_id   = hcloud_network.main.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = "10.0.1.0/24"
}
