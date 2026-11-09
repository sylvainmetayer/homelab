# Tests de la copie jetable de la VM docker (drill.tf) : éteinte par défaut,
# et isolée de la production quand elle existe. Mêmes simulacres que
# pangolin.tftest.hcl ; `command = plan` seulement.

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

run "drill_is_off_by_default" {
  command = plan

  assert {
    condition     = length(hcloud_server.drill) == 0 && length(hcloud_firewall.drill) == 0 && length(tls_private_key.drill_host) == 0
    error_message = "La copie jetable ne doit rien créer tant que drill.enabled n'est pas passé à true."
  }
}

run "drill_is_isolated_from_production" {
  command = plan

  variables {
    drill = {
      enabled           = true
      allowed_ssh_cidrs = ["203.0.113.7/32"]
    }
  }

  assert {
    condition     = length(hcloud_server.drill[0].network) == 0
    error_message = "La copie ne doit être attachée à aucun réseau privé : ni Pangolin, ni flip, ni NAT."
  }

  assert {
    condition     = one(hcloud_server.drill[0].public_net).ipv4_enabled == true && one(hcloud_server.drill[0].public_net).ipv6_enabled == false
    error_message = "IPv4 publique seule : le pare-feu ne filtre pas ce qui n'a pas de règle IPv6."
  }

  assert {
    condition     = hcloud_server.drill[0].labels["role"] == "drill" && hcloud_server.drill[0].location == "fsn1" && hcloud_server.drill[0].backups == false
    error_message = "Label role=drill (groupe Ansible de hetzner.py), fsn1 (le datacenter de la Storage Box), sans sauvegarde Hetzner."
  }

  assert {
    condition     = contains([for id in hcloud_server.drill[0].firewall_ids : tostring(id)], tostring(hcloud_firewall.drill[0].id))
    error_message = "Le pare-feu hcloud_firewall.drill doit être attaché à la copie."
  }

  # Seul SSH entre, et seulement depuis les adresses données.
  assert {
    condition = (
      length([for r in hcloud_firewall.drill[0].rule : r if r.direction == "in"]) == 1 &&
      [for r in hcloud_firewall.drill[0].rule : r if r.direction == "in"][0].protocol == "tcp" &&
      [for r in hcloud_firewall.drill[0].rule : r if r.direction == "in"][0].port == "22" &&
      toset([for r in hcloud_firewall.drill[0].rule : r if r.direction == "in"][0].source_ips) == toset(["203.0.113.7/32"])
    )
    error_message = "En entrée, uniquement tcp/22 depuis drill.allowed_ssh_cidrs : les ports publiés par Docker (8090, 9428) doivent rester fermés."
  }

  # Sortie en liste blanche : ni SMTP, ni IMAP, ni SSH vers l'extérieur.
  assert {
    condition = length(setintersection(
      toset([for r in hcloud_firewall.drill[0].rule : "${r.protocol}/${coalesce(r.port, "-")}" if r.direction == "out"]),
      toset(["tcp/25", "tcp/465", "tcp/587", "tcp/2525", "tcp/143", "tcp/993", "tcp/22"])
    )) == 0
    error_message = "La sortie de la copie ne doit permettre ni SMTP, ni IMAP, ni SSH : une appli restaurée écrirait avec les identifiants de la production."
  }

  assert {
    condition = contains(
      [for r in hcloud_firewall.drill[0].rule : "${r.protocol}/${coalesce(r.port, "-")}" if r.direction == "out"],
      "tcp/23"
    )
    error_message = "La sortie doit garder tcp/23, le SSH de la Storage Box (borg)."
  }
}

run "drill_refuses_ssh_open_to_the_world" {
  command = plan

  variables {
    drill = {
      enabled           = true
      allowed_ssh_cidrs = ["0.0.0.0/0"]
    }
  }

  expect_failures = [var.drill]
}

run "drill_needs_an_ssh_address" {
  command = plan

  variables {
    drill = {
      enabled = true
    }
  }

  expect_failures = [var.drill]
}
