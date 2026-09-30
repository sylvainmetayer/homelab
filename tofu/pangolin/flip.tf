# Serveur dédié à Flip Planning (production + démo, voir ansible/flip.yml).
#
# Aucune IP publique : il n'existe que sur le réseau privé, et c'est Pangolin
# qui l'atteint, à travers le newt qui tourne dessus (site "flip" dans
# tofu/pangolin_config/nodes.tf). Deux conséquences :
#
# - la sortie vers Internet (apt, pull des images, newt → Pangolin, borgmatic →
#   Storage Box) passe par Pangolin, qui fait NAT : route 0.0.0.0/0 ci-dessous,
#   rôles Ansible nat_gateway (Pangolin) et nat_client (flip) ;
# - Ansible s'y connecte par un ProxyJump via Pangolin en local
#   (inventory/hetzner.py) et par la ressource privée flip.internal en CI
#   (tofu/pangolin_config/private_resources.tf).
#
# Pas de pare-feu Hetzner : ils ne s'appliquent qu'aux interfaces publiques.
# Le filtrage entrant est fait par ufw (rôle security).
resource "hcloud_server" "flip" {
  lifecycle {
    ignore_changes = [user_data]
  }

  backups     = false
  name        = var.flip_server.name
  server_type = var.flip_server.server_type
  image       = var.flip_server.image
  location    = var.location

  ssh_keys = [hcloud_ssh_key.keepassxc.id]

  # IP fixe : c'est la destination de la ressource privée flip.internal, et
  # une adresse attribuée par DHCP pourrait changer à la recréation.
  network {
    network_id = hcloud_network.main.id
    ip         = var.flip_server.private_ip
  }

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  labels = var.labels

  user_data = templatefile("${path.root}/user_data_flip.yaml", {
    public_ssh_key = file("${path.root}/../../keys/perso.pub")
  })

  # Recommandé par le provider pour un bloc `network` inline : sans le subnet,
  # l'attachement échoue à la création.
  depends_on = [hcloud_network_subnet.main]
}
