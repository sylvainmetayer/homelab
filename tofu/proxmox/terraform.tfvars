# Configuration Proxmox
proxmox_url  = "https://pve.sylvain.cloud:8006/"
proxmox_node = "proxmox"

newt_lxc = {
  vm_id       = 200
  hostname    = "newt"
  template_id = 9001
  cores       = 1
  # 1 Gio : Newt, l'agent Beszel et Blocky (ansible/roles/blocky, jusqu'à
  # 384 Mio avec ses listes) : 512 Mio ne suffisent plus. Mise à jour en
  # place du LXC (tofu apply), avant le premier lxc.yml avec Blocky.
  memory    = 1024
  disk_size = 8
  storage   = "local-lvm"
  bridge    = "vmbr0"
}

# Configuration Debian 13 (vérifier la somme SHA512 sur https://cloud.debian.org/images/cloud/trixie/latest/)
# Image datée (pas « latest », dont le contenu change à chaque publication et
# ne correspond plus à la somme) : celle dont la VM docker a été construite.
debian13_image_url      = "https://cloud.debian.org/images/cloud/trixie/20260826-2582/debian-13-generic-amd64-20260826-2582.qcow2"
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
