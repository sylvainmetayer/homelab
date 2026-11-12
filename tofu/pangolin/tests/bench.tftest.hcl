# Tests du serveur jetable de mesure du solveur (bench.tf) : éteint par
# défaut, sans IP publique quand il existe. Mêmes simulacres que
# drill.tftest.hcl ; `command = plan` seulement.

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

run "bench_is_off_by_default" {
  command = plan

  assert {
    condition     = length(hcloud_server.bench) == 0 && length(tls_private_key.bench_host) == 0
    error_message = "Le serveur de mesure ne doit rien créer tant que bench.enabled n'est pas passé à true."
  }
}

run "bench_is_private_only" {
  command = plan

  variables {
    bench = {
      enabled = true
    }
  }

  assert {
    condition     = one(hcloud_server.bench[0].public_net).ipv4_enabled == false && one(hcloud_server.bench[0].public_net).ipv6_enabled == false
    error_message = "Le serveur de mesure ne doit avoir aucune IP publique."
  }

  assert {
    condition     = hcloud_server.bench[0].backups == false && hcloud_server.bench[0].labels.role == "bench"
    error_message = "Le serveur de mesure porte le label role=bench et aucune sauvegarde Hetzner."
  }

  assert {
    condition     = one(hcloud_server.bench[0].network).ip == "10.0.1.30" && hcloud_server.bench[0].name == "flip-bench-ccx13"
    error_message = "Le premier serveur de mesure est flip-bench-<type>, en 10.0.1.30 : hors des adresses de Pangolin et de flip."
  }
}
