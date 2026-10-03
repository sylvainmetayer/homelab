# Tests du module tofu/proxmox : VM Docker (toutes les apps) et LXC Newt.
#
# Aucun backend, aucun credential, aucune clé SOPS : tous les providers sont
# mockés et la data source SOPS est surchargée. Les variables viennent de
# terraform.tfvars, chargé automatiquement par `tofu test`.
#
# Les valeurs calculées d'un provider mocké sont inconnues au plan : les
# assertions ne portent que sur des valeurs issues de la configuration.

# Le provider valide dès le plan que les file_id référencés ont la forme
# `datastore:type/fichier` : les identifiants aléatoires du mock ne passent pas.
mock_provider "proxmox" {
  mock_resource "proxmox_virtual_environment_download_file" {
    defaults = {
      id = "local:iso/mock-image.img"
    }
  }

  mock_resource "proxmox_virtual_environment_file" {
    defaults = {
      id = "local:snippets/mock-cloud-init.yaml"
    }
  }
}
mock_provider "sops" {}
mock_provider "random" {}

# Toutes les clés lues par secrets.tf.
override_data {
  target = data.sops_file.secrets
  values = {
    data = {
      PROXMOX_TOKEN            = "fake@pve!tofu=00000000-0000-0000-0000-000000000000"
      newt_lxc_pangolin_id     = "fake-newt-id"
      newt_lxc_pangolin_secret = "fake-newt-secret"
    }
  }
}

# Doctrine de AGENTS.md : 3 cœurs / 12 GiB, disque rotatif ; les mem_limit des
# composes sont calibrées sur cette RAM fixe.
run "docker_vm_sizing" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.docker.cpu[0].cores == 3
    error_message = "La VM Docker doit avoir 3 cœurs (doctrine de ressources de AGENTS.md)."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.docker.memory[0].dedicated == 12288
    error_message = "La VM Docker doit avoir 12 GiB de RAM (doctrine de ressources de AGENTS.md)."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.docker.memory[0].floating == 0
    error_message = "Le ballooning de la VM Docker doit rester désactivé : les mem_limit sont calibrées sur une RAM fixe."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.docker.disk[0].ssd == false
    error_message = "Le disque de la VM Docker est rotatif : ne pas l'annoncer comme SSD."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.docker.disk[0].iothread == true && proxmox_virtual_environment_vm.docker.disk[0].interface == "virtio0"
    error_message = "Le disque de la VM Docker doit rester en virtio0 avec iothread."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.docker.agent[0].enabled == true
    error_message = "Le qemu-guest-agent doit rester activé (adresses observées lues par ansible/inventory/proxmox.py)."
  }
}

# ansible/inventory/proxmox.py nomme l'hôte d'après `name` et prend en priorité
# l'adresse statique du cloud-init ip_config, si elle est dans le LAN.
run "docker_vm_matches_inventory" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.docker.name == "docker"
    error_message = "La VM Docker doit s'appeler docker : c'est le nom d'hôte de l'inventaire proxmox.py (host_vars/docker, hosts: docker)."
  }

  assert {
    condition     = fileexists("${path.module}/../../ansible/host_vars/${proxmox_virtual_environment_vm.docker.name}/variables.yaml")
    error_message = "Le nom de la VM Docker doit correspondre à son dossier ansible/host_vars/."
  }

  assert {
    condition     = strcontains(file("${path.module}/../../ansible/docker.yml"), "hosts: ${proxmox_virtual_environment_vm.docker.name}")
    error_message = "Le nom de la VM Docker doit être celui que vise ansible/docker.yml."
  }

  assert {
    condition     = can(cidrhost(proxmox_virtual_environment_vm.docker.initialization[0].ip_config[0].ipv4[0].address, 0))
    error_message = "L'adresse de la VM Docker doit être statique (CIDR), pas dhcp : proxmox.py la préfère à l'adresse observée."
  }

  assert {
    condition     = cidrcontains("192.168.0.0/16", split("/", proxmox_virtual_environment_vm.docker.initialization[0].ip_config[0].ipv4[0].address)[0])
    error_message = "L'adresse de la VM Docker doit être dans le LAN_CIDR par défaut de proxmox.py (192.168.0.0/16)."
  }

  assert {
    condition     = cidrcontains(proxmox_virtual_environment_vm.docker.initialization[0].ip_config[0].ipv4[0].address, proxmox_virtual_environment_vm.docker.initialization[0].ip_config[0].ipv4[0].gateway)
    error_message = "La passerelle de la VM Docker doit être dans son sous-réseau."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.docker.node_name == var.proxmox_node
    error_message = "La VM Docker doit être sur le nœud var.proxmox_node."
  }
}

run "docker_vm_cloud_init" {
  command = plan

  assert {
    condition     = strcontains(proxmox_virtual_environment_file.docker_user_config.source_raw[0].data, "- name: sylvain")
    error_message = "Le cloud-init de la VM Docker doit créer l'utilisateur sylvain (utilisateur SSH d'Ansible)."
  }

  assert {
    condition     = strcontains(proxmox_virtual_environment_file.docker_user_config.source_raw[0].data, trimspace(file("${path.module}/../../keys/perso.pub")))
    error_message = "Le cloud-init de la VM Docker doit autoriser keys/perso.pub."
  }

  assert {
    condition     = startswith(trimspace(proxmox_virtual_environment_file.docker_user_config.source_raw[0].data), "#cloud-config") && startswith(trimspace(proxmox_virtual_environment_file.docker_vendor_config.source_raw[0].data), "#cloud-config")
    error_message = "Les snippets user/vendor de la VM Docker doivent être des documents cloud-config."
  }

  assert {
    condition     = strcontains(proxmox_virtual_environment_file.docker_vendor_config.source_raw[0].data, "qemu-guest-agent")
    error_message = "Le vendor-config doit installer le qemu-guest-agent (agent activé sur la VM)."
  }

  assert {
    condition     = proxmox_virtual_environment_file.docker_user_config.content_type == "snippets" && proxmox_virtual_environment_file.docker_vendor_config.content_type == "snippets"
    error_message = "Les fichiers cloud-init doivent être des snippets Proxmox."
  }
}

# L'image cloud Debian est téléchargée par Proxmox : sans somme de contrôle,
# une image corrompue ou altérée passerait.
run "debian_image_is_checksummed" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_download_file.debian_13.checksum_algorithm == "sha512"
    error_message = "L'image Debian 13 doit être vérifiée en SHA-512."
  }

  assert {
    condition     = can(regex("^[0-9a-f]{128}$", proxmox_virtual_environment_download_file.debian_13.checksum))
    error_message = "La somme de contrôle de l'image Debian 13 doit être un SHA-512 hexadécimal (128 caractères), pas vide."
  }
}

run "newt_lxc" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.newt.unprivileged == true
    error_message = "Le LXC Newt doit rester non privilégié."
  }

  assert {
    condition     = proxmox_virtual_environment_container.newt.features[0].nesting == false
    error_message = "Le nesting doit rester désactivé sur le LXC Newt."
  }

  assert {
    condition     = proxmox_virtual_environment_container.newt.vm_id == var.newt_lxc.vm_id
    error_message = "Le LXC Newt doit garder l'ID var.newt_lxc.vm_id."
  }

  assert {
    condition     = contains(proxmox_virtual_environment_container.newt.initialization[0].user_account[0].keys, trimspace(file("${path.module}/../../keys/perso.pub")))
    error_message = "Le LXC Newt doit autoriser keys/perso.pub."
  }

  assert {
    condition     = cidrcontains("192.168.0.0/16", split("/", proxmox_virtual_environment_container.newt.initialization[0].ip_config[0].ipv4[0].address)[0])
    error_message = "L'adresse du LXC Newt doit être statique et dans le LAN (192.168.0.0/16)."
  }

  assert {
    condition     = split("/", proxmox_virtual_environment_container.newt.initialization[0].ip_config[0].ipv4[0].address)[0] != split("/", proxmox_virtual_environment_vm.docker.initialization[0].ip_config[0].ipv4[0].address)[0]
    error_message = "Le LXC Newt et la VM Docker ne doivent pas avoir la même adresse IP."
  }
}
