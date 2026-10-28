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

  # prevent_destroy ne protège que de tofu : la protection de l'API refuse
  # aussi la suppression depuis la console Hetzner ou un autre client (un
  # jeton hcloud volé, une fausse manipulation). La lever d'abord pour
  # supprimer la box, ici ou dans la console.
  delete_protection = true

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
  # pas les 9 derniers jours. Après les sauvegardes de la nuit (borgmatic à
  # 01:00, heure de Paris) ; l'heure est en UTC.
  snapshot_plan = {
    # Une BX11 garde 10 snapshots au plus (l'API refuse au-delà) : 9
    # automatiques laissent une place à un snapshot manuel.
    max_snapshots = 9
    hour          = 3
    minute        = 0
  }
}

# ---------------------------------------------------------------------------
# Sous-compte en lecture seule du test de restauration (1er et 15 du mois)
# (.github/workflows/restore-test.yaml, issue #444).
#
# Les dépôts borg sont sous backup/<hôte>/<app>, chacun écrit par le
# sous-compte de son hôte (storage_box_subaccounts.tf). Celui-ci voit tout
# backup/ (home_directory = le dossier de backup_storage_box_path,
# group_vars/all), donc les dépôts de tous les hôtes, mais le système de
# fichiers lui refuse toute écriture, quel que soit le client : sa clé, dans
# un environnement GitHub Actions, ne peut rien supprimer. borg 1.x pose un
# verrou même pour lire : la CI appelle donc borg avec --bypass-lock.
#
# Pas d'attribut ssh_keys sur un sous-compte : il lit ses clés dans
# <home_directory>/.ssh/authorized_keys, que le compte principal dépose
# (ansible/backup.yaml, depuis l'output storage_box_restore_test_ssh_public_key).
# ---------------------------------------------------------------------------

resource "random_password" "storage_box_restore_test_password" {
  length           = 50
  special          = true
  override_special = "!$/"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "tls_private_key" "storage_box_restore_test" {
  algorithm = "ED25519"
}

resource "hcloud_storage_box_subaccount" "restore_test" {
  storage_box_id = hcloud_storage_box.backups.id
  home_directory = "backup"
  password       = random_password.storage_box_restore_test_password.result

  # Optional+computed : épinglés, sinon un plan ne verrait pas une dérive
  # faite dans la console.
  name        = "restore-test"
  description = "Test de restauration des 1er et 15 (GitHub Actions), lecture seule"
  labels      = var.labels

  access_settings = {
    readonly             = true
    ssh_enabled          = true
    reachable_externally = true
    samba_enabled        = false
    webdav_enabled       = false
  }
}
