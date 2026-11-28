# Tests du VPS OVH de la démo (demo_planning.tf) : rien tant qu'il n'est pas
# importé, puis son IPv4 en sortie pour l'inventaire. Mêmes simulacres que
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
  target = hcloud_firewall.drill
  values = {
    id = "4343"
  }
}

override_resource {
  target = hcloud_ssh_key.keepassxc
  values = {
    id = "77"
  }
}

override_data {
  target = data.ovh_vps.demo_planning
  values = {
    ips = ["2001:db8::4", "198.51.100.4"]
  }
}

run "demo_vps_absent_until_imported" {
  command = plan

  assert {
    condition     = length(ovh_vps.demo_planning) == 0 && output.demo_planning_ipv4 == ""
    error_message = "Sans demo_planning_vps, rien ne doit être déclaré (une ressource ovh_vps sans state passerait commande)."
  }
}

run "demo_vps_gives_its_ipv4" {
  command = plan

  variables {
    demo_planning_vps = "vps-1234abcd.vps.ovh.net"
  }

  assert {
    condition     = output.demo_planning_ipv4 == "198.51.100.4"
    error_message = "La sortie demo_planning_ipv4 doit être l'IPv4 du VPS, pas son IPv6."
  }
}
