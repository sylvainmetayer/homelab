# Serveur jetable de mesure du solveur de Flip Planning : même forme que flip
# (réseau privé seul, sortie par le NAT de Pangolin, SSH par rebond), avec un
# autre type de serveur, pour comparer la vitesse d'un cœur. Éteint par défaut
# (var.bench.enabled) : count = 0.
#
# - aucune IP publique, aucune ressource Pangolin, pas de newt : on n'y entre
#   qu'en SSH par le bastion, et le solveur se lance en curl sur localhost ;
# - label role=bench : hetzner.py en fait le groupe Ansible `bench`, qui n'est
#   ni hetzner ni flip, et qu'aucun playbook ne vise ;
# - la clé d'hôte SSH est générée ici et injectée par cloud-init, comme pour
#   drill : les lignes known_hosts se dérivent du state (bench_known_hosts_lines).
#
# Il reçoit une copie de la base de production (données personnelles réelles) :
# la destruction (`tofu apply` sans -var bench) fait partie de la mesure.

# `enabled` ne se met qu'en `-var`, jamais dans terraform.tfvars : un `apply`
# ordinaire doit le détruire.
variable "bench" {
  description = "Serveur Hetzner Cloud jetable pour mesurer le solveur de Flip Planning (éteint par défaut)"
  type = object({
    enabled = optional(bool, false)
    # Un serveur par type, mesurés côte à côte : flip-bench-<type>.
    server_types = optional(list(string), ["ccx13"])
    image        = optional(string, "debian-13")
    # Premier hôte pris dans hcloud_network_subnet.main (10.0.1.0/24) : le
    # serveur de rang i reçoit 10.0.1.(first_host + i). Pangolin est en .2,
    # flip en .10.
    first_host = optional(number, 30)
  })
  default = {}

  validation {
    condition     = var.bench.first_host > 10 && var.bench.first_host + length(var.bench.server_types) <= 255
    error_message = "bench.first_host : au-delà des adresses de Pangolin et de flip, et dans le /24."
  }
}

locals {
  bench_types = var.bench.enabled ? var.bench.server_types : []
  bench_ips   = [for i, t in local.bench_types : cidrhost(hcloud_network_subnet.main.ip_range, var.bench.first_host + i)]
}

resource "tls_private_key" "bench_host" {
  count     = length(local.bench_types)
  algorithm = "ED25519"
}

resource "hcloud_server" "bench" {
  count = length(local.bench_types)

  # Jetable : pas de prevent_destroy. Les sauvegardes Hetzner restent coupées
  # (une copie de plus des données personnelles).
  lifecycle {
    ignore_changes = [user_data]
  }

  name        = "flip-bench-${local.bench_types[count.index]}"
  server_type = local.bench_types[count.index]
  image       = var.bench.image
  location    = "fsn1"
  backups     = false

  ssh_keys = [hcloud_ssh_key.keepassxc.id]

  network {
    network_id = hcloud_network.main.id
    ip         = local.bench_ips[count.index]
  }

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  labels = merge(var.labels, { role = "bench" })

  # Le cloud-init de drill : un utilisateur, et la clé d'hôte générée ci-dessus.
  user_data = templatefile("${path.root}/user_data_drill.yaml", {
    public_ssh_key   = file("${path.root}/../../keys/perso.pub")
    host_private_key = tls_private_key.bench_host[count.index].private_key_openssh
    host_public_key  = trimspace(tls_private_key.bench_host[count.index].public_key_openssh)
  })

  depends_on = [hcloud_network_subnet.main]
}

# Lignes pour ansible/known_hosts.bench (ignoré par git ; hetzner.py le désigne
# en GlobalKnownHostsFile) : les clés publiques viennent du state, pas du
# réseau (pas de ssh-keyscan).
output "bench_known_hosts_lines" {
  description = "Lignes known_hosts des serveurs de mesure du solveur (vide s'ils sont éteints)"
  value = [
    for i, s in hcloud_server.bench :
    "${local.bench_ips[i]} ${trimspace(tls_private_key.bench_host[i].public_key_openssh)}"
  ]
}
