# Un sous-compte par hôte sauvegardé, limité à son dossier backup/<hôte> :
# root sur un hôte ne lit ni n'efface plus les dépôts Borg des autres.
#
# Le provider ne pose pas de clé SSH sur un sous-compte : la clé de root de
# chaque hôte (générée sur l'hôte par le rôle borgmatic) est déposée dans
# backup/<hôte>/.ssh/authorized_keys par ansible/backup.yaml, avec le compte
# principal. Le mot de passe ne sert qu'à l'API ; personne ne le lit.
locals {
  backup_hosts = toset(["docker", "pi", "pangolin", "flip"])
}

resource "random_password" "storage_box_subaccount" {
  for_each = local.backup_hosts

  length           = 50
  special          = true
  override_special = "!$/"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "hcloud_storage_box_subaccount" "backup" {
  for_each = local.backup_hosts

  storage_box_id = hcloud_storage_box.backups.id
  name           = "backup-${each.key}"
  description    = "Dépôts Borg de ${each.key}"
  home_directory = "backup/${each.key}"
  password       = random_password.storage_box_subaccount[each.key].result
  labels         = var.labels

  access_settings = {
    reachable_externally = true
    ssh_enabled          = true
    readonly             = false
    samba_enabled        = false
    webdav_enabled       = false
  }
}

# Lu par Ansible (clé SOPS backup_storage_box_subaccounts, recopiée après
# l'apply) : utilisateur et serveur SSH de chaque sous-compte.
output "storage_box_subaccounts" {
  description = "Sous-comptes de sauvegarde par hôte : utilisateur et serveur SSH"
  value = {
    for host, sub in hcloud_storage_box_subaccount.backup : host => {
      username = sub.username
      server   = sub.server
    }
  }
}
