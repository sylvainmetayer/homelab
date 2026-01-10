# Configuration Proxmox
proxmox_url  = "https://pve.internal:8006/"
proxmox_node = "proxmox"
pangolin_url = "https://pangolin.sylvain.cloud"

proxmox_vm = {
  name        = "debian-base"
  template_id = 9000
  cores       = 2
  memory      = 2048
  disk_size   = 20
  storage     = "local-lvm"
  bridge      = "vmbr0"
}

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
