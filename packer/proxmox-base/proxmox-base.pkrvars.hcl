# Proxmox connection
proxmox_url      = "https://pve.sylvain.cloud:8006/api2/json"
proxmox_node     = "proxmox"

# Storage
proxmox_storage     = "local-lvm"
proxmox_iso_storage = "local"

# ISO file (download Debian cloud image and upload to Proxmox)
iso_file = "local:iso/debian-13.3.0-amd64-netinst.iso"

# VM settings
vm_id        = 9000
vm_name      = "debian-base"
vm_cores     = 2
vm_memory    = 2048
vm_disk_size = "20G"

# SSH
ssh_username = "debian"
