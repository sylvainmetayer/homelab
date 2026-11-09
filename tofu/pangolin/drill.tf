# Copie jetable de la VM docker de Proxmox, sur Hetzner Cloud : exercice de
# reconstruction « depuis Borg » et, le jour d'un sinistre, hébergeur
# provisoire (docs/runbooks/reconstruction-vm-docker.md, étage 4 de
# perte-totale-maison.md). Éteinte par défaut (var.drill.enabled) : count = 0.
#
# Isolée de la production, point par point (les tests le vérifient) :
# - aucun réseau privé : ni Pangolin, ni flip, ni NAT (pas de bloc network) ;
# - IPv4 publique seule, SSH ouvert aux seules adresses de var.drill, rien
#   d'autre en entrée (les ports que publient beszel 8090 ou vmauth 9428 ne
#   sont pas joignables) ;
# - sortie en liste blanche : DNS, NTP, HTTP(S) pour apt et les images, et le
#   port 23 de la Storage Box. Ni SMTP (587, 465, 25), ni IMAP, ni SSH vers
#   un hôte de production : une appli restaurée ne peut envoyer aucun courrier
#   avec les identifiants de la vraie ;
# - label role=drill : hetzner.py en fait le groupe Ansible `drill`, qui n'est
#   ni pangolin ni flip ;
# - la clé d'hôte SSH est générée ici et injectée par cloud-init : la ligne
#   known_hosts se dérive du state (output drill_known_hosts_line).
#
# Données personnelles réelles sur un disque de fournisseur pendant l'exercice :
# la destruction (`tofu apply` sans -var drill) fait partie de la procédure.

# Éteinte par défaut. `enabled` ne se met qu'en `-var`, jamais dans
# terraform.tfvars : un `apply` ordinaire doit alors la détruire.
variable "drill" {
  description = "Serveur Hetzner Cloud jetable pour reconstruire la VM docker (éteint par défaut)"
  type = object({
    enabled     = optional(bool, false)
    name        = optional(string, "docker-drill")
    server_type = optional(string, "cx53")
    image       = optional(string, "debian-13")
    # SSH n'est ouvert qu'à ces adresses : l'IP publique du poste, en /32
    # (curl -s https://ifconfig.me). Jamais 0.0.0.0/0.
    allowed_ssh_cidrs = optional(list(string), [])
  })
  default = {}

  validation {
    condition     = !var.drill.enabled || length(var.drill.allowed_ssh_cidrs) > 0
    error_message = "drill.allowed_ssh_cidrs doit lister au moins une adresse : sans elle, SSH ne serait ouvert à personne."
  }

  validation {
    condition = alltrue([
      for c in var.drill.allowed_ssh_cidrs :
      can(cidrhost(c, 0)) && !contains(["0.0.0.0/0", "::/0"], c)
    ])
    error_message = "drill.allowed_ssh_cidrs : des CIDR valides, jamais 0.0.0.0/0 ni ::/0."
  }
}

locals {
  drill_on = var.drill.enabled ? 1 : 0

  # Sortie autorisée : dès qu'un pare-feu Hetzner a une règle « out », tout le
  # reste est refusé.
  drill_egress = [
    { protocol = "tcp", port = "53" },
    { protocol = "udp", port = "53" },
    { protocol = "udp", port = "123" },
    { protocol = "tcp", port = "80" },
    { protocol = "tcp", port = "443" },
    # Storage Box : SSH sur 23 (borg, lecture seule par le sous-compte restore-test).
    { protocol = "tcp", port = "23" },
  ]
}

resource "tls_private_key" "drill_host" {
  count     = local.drill_on
  algorithm = "ED25519"
}

resource "hcloud_firewall" "drill" {
  count  = local.drill_on
  name   = var.drill.name
  labels = merge(var.labels, { role = "drill" })

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.drill.allowed_ssh_cidrs
  }

  dynamic "rule" {
    for_each = local.drill_egress
    content {
      direction       = "out"
      protocol        = rule.value.protocol
      port            = rule.value.port
      destination_ips = local.public_ips
    }
  }

  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = local.public_ips
  }
}

resource "hcloud_server" "drill" {
  count = local.drill_on

  # Jetable : pas de prevent_destroy, la détruire est le but. Les sauvegardes
  # Hetzner restent coupées (une copie de plus des données personnelles).
  lifecycle {
    ignore_changes = [user_data]
  }

  name         = var.drill.name
  server_type  = var.drill.server_type
  image        = var.drill.image
  location     = "fsn1" # le datacenter de la Storage Box : le débit de borg
  backups      = false
  firewall_ids = [hcloud_firewall.drill[0].id]

  ssh_keys = [hcloud_ssh_key.keepassxc.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  labels = merge(var.labels, { role = "drill" })

  user_data = templatefile("${path.root}/user_data_drill.yaml", {
    public_ssh_key   = file("${path.root}/../../keys/perso.pub")
    host_private_key = tls_private_key.drill_host[0].private_key_openssh
    host_public_key  = trimspace(tls_private_key.drill_host[0].public_key_openssh)
  })
}

output "drill_ipv4" {
  description = "Adresse publique de la copie jetable de la VM docker (null si éteinte)"
  value       = one(hcloud_server.drill[*].ipv4_address)
}

# Ligne pour ansible/known_hosts.drill (hetzner.py la désigne en
# GlobalKnownHostsFile) : la clé publique vient du state, pas du réseau.
output "drill_known_hosts_line" {
  description = "Ligne known_hosts de la copie jetable (null si éteinte)"
  value = one([
    for s in hcloud_server.drill :
    "${s.ipv4_address} ${trimspace(tls_private_key.drill_host[0].public_key_openssh)}"
  ])
}
