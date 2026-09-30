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

# Configuration S3 Hetzner
s3_bucket_name        = "homelab-backup-sylvain"
s3_versioning_enabled = false
s3_endpoint           = "https://s3.eu-west-par.io.cloud.ovh.net"

# Serveur Flip Planning (réseau privé uniquement, sortie par NAT via Pangolin)
flip_server = {
  name        = "flip"
  server_type = "cx23"
  image       = "debian-13"
  private_ip  = "10.0.1.10"
}
