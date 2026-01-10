# Configuration de la VM
vm_name     = "pangolin"
server_type = "cx23"
location    = "nbg1"

# image = "debian-13"  # Image par défaut
image = "348416839" # ID du snapshot Packer

ssh_key_name = "keepassxc"

labels = {
  managed_by = "opentofu"
}

# Configuration Pangolin
pangolin_config = {
  dashboard_url = "pangolin.sylvain.cloud"
  base_domain   = "sylvain.cloud"
  log_level     = "info"
}
