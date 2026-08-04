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
debian13_image_checksum = "97675b27e69153002c4e13644e36200c8f9067f661dca00918c54f1cacbdb88d4bff8c0fbf5cf5d63a0397bdf0cc472d7a6372bae5281bf7ced756249c10f8a2"

docker_vm = {
  name      = "docker"
  vm_id     = 300
  hostname  = "apps"
  username  = "sylvain"
  cores     = 4
  memory    = 8192
  disk_size = 90
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
