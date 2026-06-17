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

lxc_apps = {
  echo = {
    vm_id        = 210
    hostname     = "echo"
    ipv4_address = "192.168.1.210/24"
    gateway      = "192.168.1.254"
    cores        = 1
    memory       = 1024
    disk_size    = 12
    storage      = "local-lvm"
    bridge       = "vmbr0"
  }
  rss = {
    vm_id        = 211
    hostname     = "rss"
    ipv4_address = "192.168.1.211/24"
    gateway      = "192.168.1.254"
    cores        = 1
    memory       = 1024
    disk_size    = 12
    storage      = "local-lvm"
    bridge       = "vmbr0"
  }
  betisier = {
    vm_id        = 212
    hostname     = "betisier"
    ipv4_address = "192.168.1.212/24"
    gateway      = "192.168.1.254"
    cores        = 2
    memory       = 2048
    disk_size    = 20
    storage      = "local-lvm"
    bridge       = "vmbr0"
  }
  monica_v4 = {
    vm_id        = 213
    hostname     = "monica-v4"
    ipv4_address = "192.168.1.213/24"
    gateway      = "192.168.1.254"
    cores        = 1
    memory       = 1024
    disk_size    = 12
    storage      = "local-lvm"
    bridge       = "vmbr0"
  }
  wiki = {
    vm_id        = 214
    hostname     = "wiki"
    ipv4_address = "192.168.1.214/24"
    gateway      = "192.168.1.254"
    cores        = 1
    memory       = 1024
    disk_size    = 12
    storage      = "local-lvm"
    bridge       = "vmbr0"
  }
  nextcloud = {
    vm_id        = 215
    hostname     = "nextcloud"
    ipv4_address = "192.168.1.215/24"
    gateway      = "192.168.1.254"
    cores        = 2
    memory       = 4096
    disk_size    = 40
    storage      = "local-lvm"
    bridge       = "vmbr0"
  }
  semaphore = {
    vm_id        = 216
    hostname     = "semaphore"
    ipv4_address = "192.168.1.216/24"
    gateway      = "192.168.1.254"
    cores        = 1
    memory       = 1024
    disk_size    = 12
    storage      = "local-lvm"
    bridge       = "vmbr0"
  }
  meerkat_crm = {
    vm_id        = 217
    hostname     = "meerkat-crm"
    ipv4_address = "192.168.1.217/24"
    gateway      = "192.168.1.254"
    cores        = 2
    memory       = 2048
    disk_size    = 20
    storage      = "local-lvm"
    bridge       = "vmbr0"
  }
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
