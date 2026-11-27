# Tests du serveur de la démo publique (demo_planning.tf) : réseau privé
# seul, aucune IP publique, ni sauvegarde Hetzner. Mêmes simulacres que
# bench.tftest.hcl ; `command = plan` seulement.

variables {
  state_encryption_passphrase = "tofu-test-passphrase-not-a-secret"
}

mock_provider "hcloud" {}
mock_provider "sops" {}
mock_provider "ovh" {}
mock_provider "random" {}

override_data {
  target = data.sops_file.secrets
  values = {
    data = {
      pangolin_password = "fake-pangolin-password-hash"
    }
  }
}

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

run "demo_planning_is_private_only" {
  command = plan

  assert {
    condition     = one(hcloud_server.demo_planning.public_net).ipv4_enabled == false && one(hcloud_server.demo_planning.public_net).ipv6_enabled == false
    error_message = "Le serveur de démo ne doit avoir aucune IP publique : Pangolin l'atteint par son newt."
  }

  assert {
    condition     = one(hcloud_server.demo_planning.network).ip == "10.0.1.20" && !hcloud_server.demo_planning.backups
    error_message = "Le serveur de démo garde son IP privée fixe (known_hosts, rebond) et n'a pas de sauvegarde Hetzner."
  }
}
