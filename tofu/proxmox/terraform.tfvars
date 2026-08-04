# Configuration Proxmox
proxmox_url  = "https://pve.sylvain.cloud:8006/"
proxmox_node = "proxmox"
pangolin_url = "https://pangolin.sylvain.cloud"

newt_lxc = {
  vm_id       = 200
  hostname    = "newt"
  template_id = 9001
  cores       = 1
  memory      = 512
  disk_size   = 8
  storage     = "local-lvm"
  bridge      = "vmbr0"
}

# Configuration Debian 13 (vérifier la somme SHA512 sur https://cloud.debian.org/images/cloud/trixie/latest/)
debian13_image_checksum = "720d9a2d21167e8aa1bb86a8a816658c7beaeec6975c376e15a0761383a869a466cbf7fe11c287c989020070309889dd81c37cd412290531245e3562334e05f3"

docker_vm = {
  name      = "docker"
  vm_id     = 300
  hostname  = "apps"
  username  = "sylvain"
  cores     = 3
  memory    = 12288
  disk_size = 190
  storage   = "local-lvm"
  bridge    = "vmbr0"
}

# Un disque par service nécessitant une BDD isolée sur le storage Proxmox
# "iscsi-lvm" (LUN iSCSI NAS "docker-pool" — voir
# nas-storage-docker/homelab-storage-architecture.md, section 2). Prérequis :
# le storage "iscsi-lvm" doit déjà exister côté Proxmox avant `tofu apply`.
docker_vm_data_disks = {
  demo_test = { size_gb = 10 }
}
