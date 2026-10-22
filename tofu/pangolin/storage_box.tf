resource "random_password" "storage_box_password" {
  length           = 50
  special          = true
  override_special = "!$/"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "tls_private_key" "storage_box" {
  algorithm = "ED25519"
}

resource "hcloud_storage_box" "backups" {
  name             = "backups"
  storage_box_type = "bx11"
  location         = "fsn1"
  labels           = var.labels
  password         = random_password.storage_box_password.result

  ssh_keys = [
    trimspace(tls_private_key.storage_box.public_key_openssh),
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
}

# ---------------------------------------------------------------------------
# Sous-compte en lecture seule du test de restauration (1er et 15 du mois)
# (.github/workflows/restore-test.yaml, issue #444).
#
# La CI ne reçoit jamais la clé du compte principal, qui peut tout supprimer :
# ce sous-compte ne voit que les dépôts borg (home_directory = le dossier de
# backup_storage_box_path, group_vars/all) et le système de fichiers lui
# refuse toute écriture, quel que soit le client. borg 1.x pose un verrou
# même pour lire : la CI appelle donc borg avec --bypass-lock.
#
# Pas d'attribut ssh_keys sur un sous-compte : il lit ses clés dans
# <home_directory>/.ssh/authorized_keys, que le compte principal écrit
# (ansible/backup.yaml, depuis l'output storage_box_restore_test_ssh_public_key).
# Lecture seule, le sous-compte ne peut pas les modifier lui-même.
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
  description = "Test de restauration mensuel (GitHub Actions), lecture seule"
  labels      = var.labels

  access_settings = {
    readonly             = true
    ssh_enabled          = true
    reachable_externally = true
    samba_enabled        = false
    webdav_enabled       = false
  }
}
