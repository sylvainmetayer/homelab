# Instance de démo publique de Flip Planning (Show HN, Reddit), seule sur son
# serveur pour qu'une vague de visiteurs ne prenne rien à la production de
# flip. ADR 0038. Même forme que flip :
#
# - aucune IP publique : réseau privé seul, sortie par le NAT de Pangolin
#   (nat_gateway couvre tout 10.0.0.0/16), SSH par rebond via le bastion
#   (inventory/hetzner.py, groupe `hetzner` comme flip) ;
# - Pangolin l'atteint par le newt qui tourne dessus (site "demo-planning",
#   tofu/pangolin_config/nodes.tf), ressource website_demo_planning.tf ;
# - configuré par ansible/demo-planning.yml, jamais par la CI ;
# - sortie filtrée sur l'hôte (rôle flip_planning_demo, nftables) : les
#   conteneurs ne joignent que Pangolin (newt), l'hôte DNS, NTP et HTTP(S),
#   rien vers le réseau privé (flip, les ports privés de Pangolin). Les
#   pare-feu Hetzner ne couvrent pas le réseau privé.
#
# Aucune donnée réelle : la base est remise au dump de référence toutes les
# 30 min, sans sauvegarde. D'où ni prevent_destroy, ni backups Hetzner.
variable "demo_planning_server" {
  description = "Serveur de la démo publique de Flip Planning (réseau privé uniquement)"
  type = object({
    name        = optional(string, "demo-planning")
    server_type = optional(string, "cx23")
    image       = optional(string, "debian-13")
    # Dans hcloud_network_subnet.main (10.0.1.0/24) : Pangolin en .2, flip en
    # .10, les serveurs bench à partir de .30.
    private_ip = optional(string, "10.0.1.20")
  })
  default = {}
}

# Clé d'hôte générée ici et injectée par cloud-init, comme pour bench et drill :
# la ligne de ansible/known_hosts se tire du state (output
# demo_planning_known_hosts_line), jamais d'un ssh-keyscan.
resource "tls_private_key" "demo_planning_host" {
  algorithm = "ED25519"
}

resource "hcloud_server" "demo_planning" {
  lifecycle {
    ignore_changes = [user_data]
  }

  backups     = false
  name        = var.demo_planning_server.name
  server_type = var.demo_planning_server.server_type
  image       = var.demo_planning_server.image
  location    = "fsn1"

  ssh_keys = [hcloud_ssh_key.keepassxc.id]

  # IP fixe : celle que vise la ligne known_hosts, et la cible du rebond.
  network {
    network_id = hcloud_network.main.id
    ip         = var.demo_planning_server.private_ip
  }

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  labels = var.labels

  user_data = templatefile("${path.root}/user_data_demo_planning.yaml", {
    public_ssh_key   = file("${path.root}/../../keys/perso.pub")
    host_private_key = tls_private_key.demo_planning_host.private_key_openssh
    host_public_key  = trimspace(tls_private_key.demo_planning_host.public_key_openssh)
  })

  depends_on = [hcloud_network_subnet.main]
}

# À ajouter à ansible/known_hosts après la création (clé publique, versionnable).
output "demo_planning_known_hosts_line" {
  description = "Ligne known_hosts du serveur de démo, à ajouter à ansible/known_hosts"
  value       = "${var.demo_planning_server.private_ip} ${trimspace(tls_private_key.demo_planning_host.public_key_openssh)}"
}
