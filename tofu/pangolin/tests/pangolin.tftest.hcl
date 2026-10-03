# Tests du module tofu/pangolin : VM Pangolin, serveur flip (réseau privé
# uniquement), route NAT, pare-feu et Storage Box.
#
# Aucun backend, aucun credential, aucune clé SOPS : tous les providers sont
# mockés et la data source SOPS est surchargée. Toutes les runs sont en
# `command = plan` : les serveurs et la Storage Box portent un
# prevent_destroy, qui ferait échouer le nettoyage d'une run en apply.
#
# Les valeurs calculées d'un provider mocké sont inconnues au plan : les
# assertions portent sur des valeurs issues de la configuration, ou sur des
# ressources surchargées (override_resource) dont les valeurs sont connues.

mock_provider "hcloud" {}
mock_provider "sops" {}
mock_provider "ovh" {}
mock_provider "aws" {}
mock_provider "random" {}
mock_provider "tls" {}

# Toutes les clés lues par secrets.tf.
override_data {
  target = data.sops_file.secrets
  values = {
    data = {
      pangolin_password     = "fake-pangolin-password-hash"
      pangolin_secret       = "fake-pangolin-secret"
      smtp_user             = "fake-smtp-user"
      smtp_pass             = "fake-smtp-pass"
      le_email              = "fake@example.invalid"
      AWS_ACCESS_KEY_ID     = "fake-access-key"
      AWS_SECRET_ACCESS_KEY = "fake-secret-key"
    }
  }
}

# IDs fixés (numériques, comme chez Hetzner) : network_id et firewall_ids
# sont des nombres côté provider, et des IDs inconnus rendraient inconnus les
# attributs qui les référencent.
override_resource {
  target = hcloud_network.main
  values = {
    id = "1234"
  }
}

override_resource {
  target = hcloud_firewall.pangolin
  values = {
    id = "4242"
  }
}

override_resource {
  target = hcloud_ssh_key.keepassxc
  values = {
    id = "77"
  }
}

run "flip_has_no_public_ip" {
  command = plan

  assert {
    condition     = one(hcloud_server.flip.public_net).ipv4_enabled == false
    error_message = "flip ne doit pas avoir d'IPv4 publique : il n'est joignable que par le réseau privé, via Pangolin."
  }

  assert {
    condition     = one(hcloud_server.flip.public_net).ipv6_enabled == false
    error_message = "flip ne doit pas avoir d'IPv6 publique : il n'est joignable que par le réseau privé, via Pangolin."
  }

  assert {
    condition     = length(hcloud_server.flip.network) == 1
    error_message = "flip doit être attaché à exactement un réseau privé."
  }

  assert {
    condition     = tostring(one(hcloud_server.flip.network).network_id) == tostring(hcloud_network.main.id)
    error_message = "flip doit être attaché au réseau privé hcloud_network.main, celui que Pangolin route en NAT."
  }

  assert {
    condition     = hcloud_server.flip.backups == false
    error_message = "Les backups Hetzner de flip sont désactivés (Borgmatic s'en charge) : un changement ici doit être voulu."
  }
}

run "flip_private_ip_is_stable" {
  command = plan

  assert {
    condition     = one(hcloud_server.flip.network).ip == var.flip_server.private_ip
    error_message = "L'IP privée de flip doit être fixée par var.flip_server.private_ip, pas attribuée par DHCP."
  }

  assert {
    condition     = cidrcontains(hcloud_network_subnet.main.ip_range, one(hcloud_server.flip.network).ip)
    error_message = "L'IP privée de flip doit appartenir au subnet hcloud_network_subnet.main."
  }

  assert {
    condition     = one(hcloud_server.flip.network).ip != cidrhost(hcloud_network.main.ip_range, 1)
    error_message = "L'IP privée de flip ne peut pas être la passerelle du réseau Hetzner (x.x.x.1)."
  }

  # L'inventaire CI vise flip par son IP privée en dur.
  assert {
    condition     = strcontains(file("${path.module}/../../.github/workflows/deploy-docker-app.yaml"), "flip ansible_host=${one(hcloud_server.flip.network).ip}")
    error_message = "L'IP privée de flip doit rester en phase avec l'inventaire CI de .github/workflows/deploy-docker-app.yaml."
  }

  # Lue par tofu/pangolin_config (remote state) pour la ressource flip.internal.
  assert {
    condition     = output.flip_private_ip == one(hcloud_server.flip.network).ip
    error_message = "L'output flip_private_ip doit exposer l'IP privée de flip (lue par tofu/pangolin_config)."
  }
}

run "nat_route_targets_pangolin" {
  command = plan

  # Pangolin surchargé : son IP privée (calculée) devient connue au plan.
  override_resource {
    target = hcloud_server.pangolin
    values = {
      ipv4_address = "203.0.113.10"
    }
  }

  assert {
    condition     = hcloud_network_route.nat.destination == "0.0.0.0/0"
    error_message = "La route NAT doit être la route par défaut (0.0.0.0/0) du réseau privé."
  }

  assert {
    condition     = tostring(hcloud_network_route.nat.network_id) == tostring(hcloud_network.main.id)
    error_message = "La route NAT doit être posée sur le réseau privé hcloud_network.main."
  }

  assert {
    condition     = hcloud_network_route.nat.gateway == one(hcloud_server.pangolin.network).ip
    error_message = "La passerelle de la route NAT doit être l'IP privée de Pangolin (rôle nat_gateway)."
  }

  assert {
    condition     = hcloud_network_route.nat.gateway != one(hcloud_server.flip.network).ip
    error_message = "La passerelle de la route NAT ne doit pas être flip : il n'a pas d'accès Internet propre."
  }

  # Lue par tofu/dns (remote state) pour les enregistrements A.
  assert {
    condition     = output.pangolin_ip == hcloud_server.pangolin.ipv4_address
    error_message = "L'output pangolin_ip doit exposer l'IPv4 publique de Pangolin (lue par tofu/dns)."
  }
}

run "private_network_matches_nat_roles" {
  command = plan

  assert {
    condition     = hcloud_network.main.ip_range == "10.0.0.0/16"
    error_message = "Le réseau privé doit rester 10.0.0.0/16 (nat_gateway_source_cidr du rôle nat_gateway)."
  }

  assert {
    condition     = cidrcontains(hcloud_network.main.ip_range, cidrhost(hcloud_network_subnet.main.ip_range, 0))
    error_message = "Le subnet doit être inclus dans le réseau privé."
  }

  assert {
    condition     = hcloud_network_subnet.main.type == "cloud" && hcloud_network_subnet.main.network_zone == "eu-central"
    error_message = "Le subnet doit être de type cloud, en zone eu-central."
  }

  assert {
    condition     = contains(["fsn1", "nbg1", "hel1"], hcloud_server.pangolin.location) && contains(["fsn1", "nbg1", "hel1"], hcloud_server.flip.location)
    error_message = "Pangolin et flip doivent être dans une location de la zone réseau eu-central, sinon ils ne peuvent pas rejoindre le réseau privé."
  }

  assert {
    condition     = strcontains(file("${path.module}/../../ansible/roles/nat_gateway/defaults/main.yml"), "nat_gateway_source_cidr: ${hcloud_network.main.ip_range}")
    error_message = "nat_gateway_source_cidr (rôle nat_gateway) doit être la plage du réseau privé."
  }

  # La passerelle d'un réseau Hetzner est toujours la première adresse de sa
  # plage : c'est elle qui applique la route NAT.
  assert {
    condition     = strcontains(file("${path.module}/../../ansible/roles/nat_client/defaults/main.yml"), "nat_client_gateway: ${cidrhost(hcloud_network.main.ip_range, 1)}")
    error_message = "nat_client_gateway (rôle nat_client) doit être la passerelle du réseau privé (première adresse de sa plage)."
  }

  assert {
    condition     = strcontains(file("${path.module}/../../ansible/roles/nat_gateway/defaults/main.yml"), "nat_gateway_private_network_gateway: ${cidrhost(hcloud_network.main.ip_range, 1)}")
    error_message = "nat_gateway_private_network_gateway (rôle nat_gateway) doit être la passerelle du réseau privé."
  }
}

# ansible/inventory/hetzner.py nomme les hôtes d'après `name` et cherche le
# bastion sous le nom HETZNER_BASTION (défaut "pangolin") ; host_vars et
# playbooks visent ces mêmes noms.
run "inventory_names_match_ansible" {
  command = plan

  assert {
    condition     = strcontains(file("${path.module}/../../ansible/inventory/hetzner.py"), "os.environ.get(\"HETZNER_BASTION\", \"${hcloud_server.pangolin.name}\")")
    error_message = "Le nom de la VM Pangolin doit rester le bastion par défaut de ansible/inventory/hetzner.py."
  }

  assert {
    condition     = fileexists("${path.module}/../../ansible/host_vars/${hcloud_server.pangolin.name}/variables.yaml")
    error_message = "Le nom de la VM Pangolin doit correspondre à son dossier ansible/host_vars/."
  }

  assert {
    condition     = fileexists("${path.module}/../../ansible/host_vars/${hcloud_server.flip.name}/variables.yaml")
    error_message = "Le nom du serveur flip doit correspondre à son dossier ansible/host_vars/."
  }

  assert {
    condition     = strcontains(file("${path.module}/../../ansible/flip.yml"), "hosts: ${hcloud_server.flip.name}")
    error_message = "Le nom du serveur flip doit être celui que vise ansible/flip.yml."
  }

  assert {
    condition     = strcontains(file("${path.module}/../../ansible/pangolin.yaml"), "hosts: ${hcloud_server.pangolin.name}")
    error_message = "Le nom de la VM Pangolin doit être celui que vise ansible/pangolin.yaml."
  }

  assert {
    condition     = fileexists("${path.module}/../../ansible/host_vars/${hcloud_storage_box.backups.name}/variables.yaml")
    error_message = "Le nom de la Storage Box doit correspondre à son dossier ansible/host_vars/ (groupe backups)."
  }
}

run "pangolin_is_the_public_bastion" {
  command = plan

  assert {
    condition     = one(hcloud_server.pangolin.public_net).ipv4_enabled == true
    error_message = "Pangolin doit avoir une IPv4 publique : DNS, tunnels newt et bastion SSH en dépendent."
  }

  assert {
    condition     = contains([for id in hcloud_server.pangolin.firewall_ids : tostring(id)], tostring(hcloud_firewall.pangolin.id))
    error_message = "Le pare-feu hcloud_firewall.pangolin doit être attaché à la VM Pangolin."
  }

  assert {
    condition     = contains([for id in hcloud_server.pangolin.ssh_keys : tostring(id)], tostring(hcloud_ssh_key.keepassxc.id)) && contains([for id in hcloud_server.flip.ssh_keys : tostring(id)], tostring(hcloud_ssh_key.keepassxc.id))
    error_message = "Pangolin et flip doivent recevoir la clé SSH keepassxc."
  }

  assert {
    condition     = tostring(one(hcloud_server.pangolin.network).network_id) == tostring(hcloud_network.main.id)
    error_message = "Pangolin doit être attaché au réseau privé pour faire NAT et bastion vers flip."
  }
}

run "firewall_exposes_only_pangolin_ports" {
  command = plan

  assert {
    condition = toset([
      for r in hcloud_firewall.pangolin.rule : "${r.direction}/${r.protocol}/${coalesce(r.port, "-")}"
      ]) == toset([
      "in/udp/51820",
      "in/udp/21820",
      "in/tcp/22",
      "in/tcp/80",
      "in/tcp/443",
      "in/icmp/-",
    ])
    error_message = "Le pare-feu Pangolin doit ouvrir exactement WireGuard (51820, 21820/udp), SSH, HTTP, HTTPS et ICMP en entrée."
  }

  assert {
    condition     = alltrue([for r in hcloud_firewall.pangolin.rule : r.direction == "in"])
    error_message = "Le pare-feu Pangolin ne doit pas filtrer la sortie : flip sort sur Internet par le NAT de Pangolin."
  }

  # Un port ouvert chez Hetzner mais pas dans ufw (rôle security) est bloqué
  # sans bruit sur la VM.
  assert {
    condition = alltrue([
      for r in hcloud_firewall.pangolin.rule :
      strcontains(file("${path.module}/../../ansible/host_vars/pangolin/variables.yaml"), "{ port: \"${r.port}\", proto: ${r.protocol} }")
      if r.protocol != "icmp"
    ])
    error_message = "Chaque port TCP/UDP du pare-feu Hetzner doit aussi figurer dans security_ufw_allowed_ports (ansible/host_vars/pangolin)."
  }
}

run "user_data_templating" {
  command = plan

  assert {
    condition     = startswith(hcloud_server.pangolin.user_data, "#cloud-config") && startswith(hcloud_server.flip.user_data, "#cloud-config")
    error_message = "Le user_data doit être un document cloud-config."
  }

  assert {
    condition     = !strcontains(hcloud_server.pangolin.user_data, "$${") && !strcontains(hcloud_server.flip.user_data, "$${")
    error_message = "Le user_data ne doit plus contenir de variable de template non résolue."
  }

  assert {
    condition     = strcontains(hcloud_server.pangolin.user_data, "passwd: fake-pangolin-password-hash")
    error_message = "Le user_data de Pangolin doit porter le hash du mot de passe lu dans SOPS (pangolin_password)."
  }

  assert {
    condition     = strcontains(hcloud_server.pangolin.user_data, trimspace(hcloud_ssh_key.keepassxc.public_key)) && strcontains(hcloud_server.flip.user_data, trimspace(hcloud_ssh_key.keepassxc.public_key))
    error_message = "Le user_data de Pangolin et de flip doit autoriser la clé keys/perso.pub."
  }

  assert {
    condition     = trimspace(hcloud_ssh_key.keepassxc.public_key) == trimspace(file("${path.module}/../../keys/perso.pub"))
    error_message = "La clé SSH Hetzner keepassxc doit être keys/perso.pub."
  }

  # flip n'a pas de mot de passe : accès par clé uniquement.
  assert {
    condition     = strcontains(hcloud_server.flip.user_data, "lock_passwd: true") && !strcontains(hcloud_server.flip.user_data, "fake-pangolin-password-hash")
    error_message = "Le user_data de flip doit verrouiller le mot de passe et ne pas porter celui de Pangolin."
  }

  assert {
    condition     = strcontains(hcloud_server.pangolin.user_data, "ssh_pwauth: false") && strcontains(hcloud_server.flip.user_data, "ssh_pwauth: false")
    error_message = "L'authentification SSH par mot de passe doit rester désactivée."
  }
}

run "storage_box_backups" {
  command = plan

  # Clé et mot de passe générés surchargés : sinon inconnus au plan.
  override_resource {
    target = tls_private_key.storage_box
    values = {
      public_key_openssh = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeStorageBoxKey\n"
      private_key_pem    = "fake-private-key"
    }
  }

  override_resource {
    target = random_password.storage_box_password
    values = {
      result = "fake-storage-box-password"
    }
  }

  assert {
    condition     = hcloud_storage_box.backups.name == "backups"
    error_message = "La Storage Box doit s'appeler backups (nom d'hôte de l'inventaire hetzner.py et groupe Ansible backups)."
  }

  assert {
    condition     = hcloud_storage_box.backups.access_settings.ssh_enabled == true && hcloud_storage_box.backups.access_settings.reachable_externally == true
    error_message = "La Storage Box doit être joignable en SSH depuis l'extérieur (borgmatic, ansible/backup.yaml)."
  }

  assert {
    condition     = contains(hcloud_storage_box.backups.ssh_keys, "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeStorageBoxKey")
    error_message = "La Storage Box doit autoriser la clé générée tls_private_key.storage_box (sans saut de ligne final)."
  }

  assert {
    condition     = contains(hcloud_storage_box.backups.ssh_keys, trimspace(file("${path.module}/../../keys/perso.pub")))
    error_message = "La Storage Box doit autoriser keys/perso.pub."
  }

  assert {
    condition     = length(hcloud_storage_box.backups.ssh_keys) == 4
    error_message = "La Storage Box doit autoriser exactement 4 clés : générée, perso, pro et android."
  }

  assert {
    condition     = hcloud_storage_box.backups.password == "fake-storage-box-password"
    error_message = "Le mot de passe de la Storage Box doit venir de random_password.storage_box_password."
  }

  assert {
    condition     = output.storage_box_ssh_public_key == tls_private_key.storage_box.public_key_openssh
    error_message = "L'output storage_box_ssh_public_key doit exposer la clé publique générée."
  }
}
