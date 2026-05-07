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
    trimspace(tls_private_key.storage_box.public_key_openssh),
    trimspace(file("${path.root}/../../keys/perso.pub")),
    trimspace(file("${path.root}/../../ansible/roles/semaphore/files/key.pub")),
    trimspace(file("${path.root}/../../keys/pro.pub")),
    trimspace(file("${path.root}/../../keys/android.pub"))
  ]

  lifecycle {
    prevent_destroy = true
    ignore_changes = [ssh_keys]
  }

  access_settings = {
    reachable_externally = true
    ssh_enabled = true
  }
}
