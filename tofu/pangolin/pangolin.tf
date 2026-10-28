locals {
  public_ips = [
    "0.0.0.0/0",
    "::/0"
  ]
}

resource "hcloud_ssh_key" "keepassxc" {
  name       = var.ssh_key_name
  public_key = file("${path.root}/../../keys/perso.pub")
  labels     = var.labels
}

resource "hcloud_server" "pangolin" {
  lifecycle {
    # image : le serveur en place a été créé depuis un ancien snapshot Packer
    # (348416839), Packer a depuis été retiré du dépôt. Sans cet ignore, passer
    # à debian-13 forcerait son remplacement. Une reconstruction repart de
    # debian-13 nu + user_data.yaml, puis 00-setup.yaml et pangolin.yaml, puis
    # la restauration de /opt/pangolin depuis son dépôt Borg.
    ignore_changes  = [image, user_data, network]
    prevent_destroy = true
  }

  firewall_ids = [hcloud_firewall.pangolin.id]
  # Sauvegardes Hetzner (7 images glissantes, +20 % du prix du serveur) :
  # la reprise rapide, même IP et même clé d'hôte, en quelques minutes.
  # Borg reste la copie hors Hetzner (docs/runbooks/reconstruction-pangolin.md).
  backups     = true
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

  user_data = templatefile("${path.root}/user_data.yaml", {
    pangolin_password      = local.pangolin_password
    public_ssh_key         = file("${path.root}/../../keys/perso.pub")
    pangolin_dashboard_url = var.pangolin_config.dashboard_url
    pangolin_base_domain   = var.pangolin_config.base_domain
    pangolin_log_level     = var.pangolin_config.log_level
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
