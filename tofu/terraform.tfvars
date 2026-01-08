# Configuration de la VM
vm_name     = "pangolin"
server_type = "CX23"
image       = "debian-13"
location    = "nbg1"

ssh_key_name   = "keepassxc"
ssh_allowed_ips = ["0.0.0.0/0", "::/0"]

labels = {
  managed_by  = "opentofu"
}

# Script d'initialisation (optionnel) TODO Create user via cloudinit
user_data = <<-EOF
#!/bin/bash
apt-get update
apt-get upgrade -y
apt-get install -y docker.io
systemctl enable docker
systemctl start docker
EOF
