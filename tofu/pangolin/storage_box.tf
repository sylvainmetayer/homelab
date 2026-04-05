resource "random_password" "storage_box_password" {
  length  = 50
  special = true
  override_special = "!$/"
  min_upper = 1
  min_lower = 1
  min_numeric = 1
  min_special = 1
}

resource "tls_private_key" "storage_box" {
    algorithm = "ED25519"
}

resource "hcloud_storage_box" "backups" {
  name             = "backups"
  storage_box_type = "bx11"
  location         = "fsn1"
  labels     = var.labels
  password         = random_password.storage_box_password.result

  ssh_keys = [
    trimspace(file("${path.root}/../../keys/perso.pub")),
    trimspace(tls_private_key.storage_box.public_key_openssh)
  ]

  lifecycle {
    prevent_destroy = true
  }

  access_settings = {
    reachable_externally = true
    ssh_enabled = true
  }
}
