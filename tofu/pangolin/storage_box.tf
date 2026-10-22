resource "random_password" "storage_box_password" {
  length           = 50
  special          = true
  override_special = "!$/"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "hcloud_storage_box" "backups" {
  name             = "backups"
  storage_box_type = "bx11"
  location         = "fsn1"
  labels           = var.labels
  password         = random_password.storage_box_password.result

  # Compte principal : les clés personnelles seulement, les hôtes passent par
  # leur sous-compte (storage_box_subaccounts.tf). L'API ne modifie pas cette
  # liste (tout changement remplacerait la box) : la liste réelle se tient
  # dans .ssh/authorized_keys du compte principal, d'où l'ignore_changes.
  ssh_keys = [
    trimspace(file("${path.root}/../../keys/perso.pub")),
    trimspace(file("${path.root}/../../keys/pro.pub")),
    trimspace(file("${path.root}/../../keys/android.pub"))
  ]

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [ssh_keys]
  }

  access_settings = {
    reachable_externally = true
    ssh_enabled          = true
  }

  # Les sous-comptes (un par hôte, storage_box_subaccounts.tf) ne peuvent pas
  # supprimer un snapshot : root sur un hôte peut effacer ses dépôts Borg,
  # pas les 14 derniers jours. Après les sauvegardes de la nuit (borgmatic à
  # 01:00, heure de Paris) ; l'heure est en UTC.
  snapshot_plan = {
    max_snapshots = 14
    hour          = 3
    minute        = 0
  }
}
