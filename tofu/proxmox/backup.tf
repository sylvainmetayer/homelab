# Sauvegarde vzdump de la VM docker et du LXC newt, sur le NAS.
#
# Avant (job créé dans l'interface) : storage `local`, c'est-à-dire
# /var/lib/vz/dump sur la racine de l'hôte (94 Go, sur le même SSD que
# local-lvm). keep-last=2 y garde deux archives, et vzdump écrit la troisième
# avant d'élaguer : trois archives de la VM docker (25,5 Go le 29/09, ~50 Go
# depuis que son disque est passé de 61 à 133 Go écrits) ne tiennent pas, et
# le job échoue chaque soir depuis le 30/09 (« No space left on device »).
#
# Le NAS (RAID1, 3,7 To) les reçoit par NFS : export /volume1/pve-backup,
# publié par nas.yml (host_vars/nas) pour la seule IP de l'hôte.
#
# Ordre (voir docs/runbooks/sauvegarde-et-restauration.md) : dossier partagé
# créé dans UGOS, puis nas.yml, puis `tofu import` du job existant, puis apply.

locals {
  # Une seule rétention : celle du storage (sauvegardes lancées à la main
  # depuis l'interface) et celle du job.
  vzdump_keep_last = 2
}

resource "proxmox_storage_nfs" "nas_backup" {
  id     = "nas-backup"
  server = var.nas_backup.server
  export = var.nas_backup.export
  # UGOS Pro 1.20 ne sert que NFSv3 (rôle nas, nas_nfs_max_protocol).
  options = "vers=3"
  content = ["backup"]
  nodes   = [var.proxmox_node]

  backups {
    keep_last = local.vzdump_keep_last
  }
}

# Le job de l'interface, importé (id d'origine) : `tofu import
# proxmox_backup_job.nightly backup-cbfcde61-8413` avant le premier apply. Sans
# l'import, l'apply échoue sur un id déjà pris plutôt que de doubler le job.
resource "proxmox_backup_job" "nightly" {
  id       = "backup-cbfcde61-8413"
  comment  = "VM docker et LXC newt, sur le NAS (tofu/proxmox)"
  schedule = "21:00"
  storage  = proxmox_storage_nfs.nas_backup.id
  node     = var.proxmox_node
  vmid = [
    tostring(proxmox_virtual_environment_vm.docker.vm_id),
    tostring(proxmox_virtual_environment_container.newt.vm_id),
  ]
  mode              = "snapshot"
  compress          = "zstd"
  notes_template    = "{{guestname}}"
  notification_mode = "notification-system"
  repeat_missed     = true
  # Pas de tmpdir ici : l'API le réserve à root@pam (HTTP 400 « Only root
  # may set this option » avec le jeton de Tofu). Il est dans
  # /etc/vzdump.conf, posé par pve.yml, et vaut aussi pour les sauvegardes
  # lancées à la main.
  enabled = true
  prune_backups = {
    keep-last = tostring(local.vzdump_keep_last)
  }

  # Fleecing (01/11/2026) : pendant la sauvegarde vers le NAS (NFS, lent),
  # les blocs que la VM réécrit sont copiés dans une image temporaire sur
  # local-lvm au lieu d'attendre le NAS : les applis ne se figent plus à
  # 21:00. L'image ne grossit que des écritures faites pendant le job et
  # disparaît à la fin. Sans effet sur le LXC (sauvegarde par tar).
  fleecing = {
    enabled = true
    storage = "local-lvm"
  }
}
