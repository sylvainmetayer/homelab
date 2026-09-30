# Sortie Internet des serveurs sans IP publique (flip) : le réseau privé envoie
# tout ce qui ne lui appartient pas à Pangolin, qui masquerade sur son interface
# publique (rôle Ansible nat_gateway). Côté client, la route par défaut pointe
# sur la passerelle du réseau, 10.0.0.1 (rôle nat_client) : c'est elle qui
# applique cette route.
#
# Pangolin garde sa propre route par défaut, par son interface publique : une
# route de réseau ne s'applique qu'au trafic qui entre dans le réseau privé.
resource "hcloud_network_route" "nat" {
  network_id  = hcloud_network.main.id
  destination = "0.0.0.0/0"
  gateway     = one(hcloud_server.pangolin.network).ip
}
