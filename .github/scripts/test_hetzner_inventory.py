"""hetzner.py : la copie jetable (label role=drill) n'est jamais pangolin ni flip."""
import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "ansible" / "inventory" / "hetzner.py"


def load():
    spec = importlib.util.spec_from_file_location("hetzner_inventory", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def server(name, ipv4, labels=None, private_ip=None):
    return {
        "type": "hcloud_server",
        "values": {
            "name": name,
            "ipv4_address": ipv4,
            "labels": labels or {},
            "network": [{"ip": private_ip}] if private_ip else [],
            "server_type": "cx23",
            "location": "fsn1",
        },
    }


STATE = {
    "values": {
        "outputs": {
            "storage_box_restore_test_username": {"value": "u1-sub9"},
            "storage_box_restore_test_server": {"value": "u1.your-storagebox.de"},
        },
        "root_module": {
            "resources": [
                server("pangolin", "203.0.113.1", {"managed_by": "opentofu"}),
                server("flip", None, {"managed_by": "opentofu"}, private_ip="10.0.1.10"),
                server("docker-drill", "203.0.113.9", {"role": "drill"}),
                server("flip-bench-ccx13", None, {"role": "bench"}, private_ip="10.0.1.30"),
            ]
        },
    }
}


class HetznerInventory(unittest.TestCase):
    def inventory(self, state=STATE):
        module = load()
        module.get_tofu_state = lambda: state
        return module.get_inventory()

    def test_drill_is_only_in_the_drill_group(self):
        inv = self.inventory()
        self.assertEqual(inv["drill"]["hosts"], ["docker-drill"])
        self.assertEqual(sorted(inv["hetzner"]["hosts"]), ["flip", "pangolin"])
        self.assertIn("drill", inv["all"]["children"])

    def test_drill_host_vars(self):
        host = self.inventory()["_meta"]["hostvars"]["docker-drill"]
        self.assertEqual(host["ansible_host"], "203.0.113.9")
        self.assertEqual(host["drill_borg_user"], "u1-sub9")
        self.assertEqual(host["drill_borg_server"], "u1.your-storagebox.de")
        # Clé d'hôte stricte, lue dans le fichier hors dépôt : jamais de ssh-keyscan.
        self.assertIn("GlobalKnownHostsFile=", host["ansible_ssh_common_args"])
        self.assertTrue(host["ansible_ssh_common_args"].endswith("known_hosts.drill"))
        self.assertNotIn("StrictHostKeyChecking=no", host["ansible_ssh_common_args"])
        self.assertNotIn("ProxyCommand", host["ansible_ssh_common_args"])

    def test_bench_is_only_in_the_bench_group_behind_the_bastion(self):
        inv = self.inventory()
        self.assertEqual(inv["bench"]["hosts"], ["flip-bench-ccx13"])
        self.assertNotIn("flip-bench-ccx13", inv["hetzner"]["hosts"])
        self.assertIn("flip", inv["hetzner"]["hosts"])
        host = inv["_meta"]["hostvars"]["flip-bench-ccx13"]
        self.assertEqual(host["ansible_host"], "10.0.1.30")
        self.assertIn("sylvain@203.0.113.1", host["ansible_ssh_common_args"])
        self.assertTrue(host["ansible_ssh_common_args"].endswith("known_hosts.bench"))
        self.assertNotIn("known_hosts.bench", inv["_meta"]["hostvars"]["flip"]["ansible_ssh_common_args"])

    def test_without_drill_the_group_is_empty(self):
        state = {"values": {"root_module": {"resources": [server("pangolin", "203.0.113.1")]}}}
        inv = self.inventory(state)
        self.assertEqual(inv["drill"]["hosts"], [])
        self.assertEqual(inv["hetzner"]["hosts"], ["pangolin"])


if __name__ == "__main__":
    unittest.main()
