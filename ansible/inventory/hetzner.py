#!/usr/bin/env python3
"""
Dynamic inventory script for Hetzner Cloud servers managed by OpenTofu.
Reads terraform state to generate Ansible inventory.

A server with no public IPv4 (flip) is only on the private network: it is
addressed by its private IP, through a ProxyJump via the bastion - the server
named HETZNER_BASTION, Pangolin by default, which is also its NAT gateway. The
bastion's sshd must allow local forwarding (security_ssh_allow_tcp_forwarding
in host_vars/pangolin). The CI does the same with its own inventory, see
.github/workflows/deploy-docker-app.yaml.

A server labelled role=drill (the throwaway copy of the docker VM, tofu/pangolin/
drill.tf) goes into the group `drill` and nowhere else: not in `hetzner`, never
pangolin or flip. It gets drill_borg_user / drill_borg_server (the read-only
restore-test subaccount of the Storage Box, from the state outputs) and its host
key through GlobalKnownHostsFile=ansible/known_hosts.drill, a git-ignored file
written from the drill_known_hosts_line output (docs/runbooks/reconstruction-vm-docker.md).
StrictHostKeyChecking stays on: no ssh-keyscan.

A server labelled role=bench (the throwaway solver bench of Flip Planning,
tofu/pangolin/bench.tf) is private-only like flip, reached through the same
bastion, but goes into the group `bench` and nowhere else; its host key comes
from the bench_known_hosts_lines output, in the git-ignored
ansible/known_hosts.bench.

Environment:
  HETZNER_BASTION   name of the server to jump through (default: pangolin)
"""

import json
import os
import subprocess
import sys

BASTION = os.environ.get("HETZNER_BASTION", "pangolin")
# Clés d'hôte versionnées (ansible/known_hosts), aussi pour le saut par le bastion.
KNOWN_HOSTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "known_hosts")
# Clé d'hôte de la copie jetable, hors dépôt (ligne tirée du state de tofu/pangolin).
DRILL_KNOWN_HOSTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "known_hosts.drill")
# Idem pour les serveurs de mesure du solveur (tofu/pangolin/bench.tf).
BENCH_KNOWN_HOSTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "known_hosts.bench")


def get_tofu_state():
    """Get terraform state from tofu."""
    try:
        result = subprocess.run(
            ["tofu", "show", "-json"],
            cwd="../tofu/pangolin",
            capture_output=True,
            text=True,
            check=True
        )
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        # Sans ce message, pangolin, flip et la Storage Box disparaîtraient de
        # l'inventaire sans un mot (ex. TF_VAR_state_encryption_passphrase
        # absent : le state chiffré ne se lit pas).
        print(f"hetzner.py: tofu show a échoué : {e.stderr.strip()}", file=sys.stderr)
        return None
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"hetzner.py: state de tofu/pangolin illisible : {e}", file=sys.stderr)
        return None


def get_inventory():
    """Generate Ansible inventory from tofu state."""
    inventory = {
        "_meta": {
            "hostvars": {}
        },
        "all": {
            "children": ["hetzner", "drill", "bench"]
        },
        "hetzner": {
            "hosts": []
        },
        "drill": {
            "hosts": []
        },
        "bench": {
            "hosts": []
        }
    }

    state = get_tofu_state()
    if not state:
        return inventory

    resources = state.get("values", {}).get("root_module", {}).get("resources", [])
    private_only = []

    for resource in resources:
        resource_type = resource.get("type")

        if resource_type == "hcloud_storage_box":
            values = resource.get("values", {})
            name = values.get("name", "unknown")

            # Get IPv4 address from Hetzner server
            ipv4_address = values.get("server")
            user = values.get("username")

            if ipv4_address and ipv4_address != "127.0.0.1":
                inventory["hetzner"]["hosts"].append(name)
                inventory["_meta"]["hostvars"][name] = {
                    "ansible_host": ipv4_address,
                    "ansible_user": user,
                    # Storage Boxes use port 23 for SSH access
                    "ansible_port": 23,
                    "location": values.get("location"),
                    "datacenter": values.get("datacenter")
                }

        if resource_type == "hcloud_server":
            values = resource.get("values", {})
            name = values.get("name", "unknown")

            # Get IPv4 address from Hetzner server
            ipv4_address = values.get("ipv4_address")

            if (values.get("labels") or {}).get("role") == "drill":
                # Copie jetable : son seul groupe est `drill` (ni hetzner, ni
                # pangolin, ni flip), voir tofu/pangolin/drill.tf.
                outputs = state.get("values", {}).get("outputs", {})
                inventory["drill"]["hosts"].append(name)
                inventory["_meta"]["hostvars"][name] = {
                    "ansible_host": ipv4_address,
                    "ansible_user": "sylvain",
                    # En plus de known_hosts : la clé de l'hôte vient du state.
                    "ansible_ssh_common_args": f"-o GlobalKnownHostsFile={DRILL_KNOWN_HOSTS}",
                    "drill_borg_user": outputs.get("storage_box_restore_test_username", {}).get("value"),
                    "drill_borg_server": outputs.get("storage_box_restore_test_server", {}).get("value"),
                    "server_type": values.get("server_type"),
                    "location": values.get("location")
                }
            elif (values.get("labels") or {}).get("role") == "bench" and ipv4_address and ipv4_address != "127.0.0.1":
                # Un serveur de mesure n'a jamais d'IP publique (bench.tf) : en
                # voir une, c'est un state qu'on ne reconnaît pas, et il ne doit
                # tomber dans aucun groupe.
                print(f"hetzner.py: {name!r} est étiqueté bench et a une IPv4 publique, ignoré", file=sys.stderr)
            elif ipv4_address and ipv4_address != "127.0.0.1":
                inventory["hetzner"]["hosts"].append(name)
                inventory["_meta"]["hostvars"][name] = {
                    "ansible_host": ipv4_address,
                    "ansible_user": "sylvain",
                    "server_type": values.get("server_type"),
                    "location": values.get("location"),
                    "datacenter": values.get("datacenter")
                }
            else:
                private_ips = [n.get("ip") for n in values.get("network") or [] if n.get("ip")]
                if private_ips:
                    private_only.append((name, private_ips[0], values))

    # Second pass: the bastion's public address is only known once every
    # server has been read, whatever their order in the state.
    bastion = inventory["_meta"]["hostvars"].get(BASTION, {}).get("ansible_host")
    for name, private_ip, values in private_only:
        if not bastion:
            print(f"hetzner.py: no public bastion {BASTION!r} to reach {name!r}, skipping", file=sys.stderr)
            continue
        # Serveur de mesure du solveur : son seul groupe est `bench` (aucun
        # playbook ne le vise), sa clé d'hôte vient du state.
        bench = (values.get("labels") or {}).get("role") == "bench"
        inventory["bench" if bench else "hetzner"]["hosts"].append(name)
        inventory["_meta"]["hostvars"][name] = {
            "ansible_host": private_ip,
            "ansible_user": "sylvain",
            # ProxyCommand plutôt que ProxyJump : le ssh du saut ne reçoit
            # pas les -o d'Ansible, il vérifierait le bastion contre
            # ~/.ssh/known_hosts au lieu de ansible/known_hosts.
            "ansible_ssh_common_args": (
                f'-o ProxyCommand="ssh -o UserKnownHostsFile={KNOWN_HOSTS} '
                f'-o StrictHostKeyChecking=yes -W %h:%p sylvain@{bastion}"'
                + (f" -o GlobalKnownHostsFile={BENCH_KNOWN_HOSTS}" if bench else "")
            ),
            "server_type": values.get("server_type"),
            "location": values.get("location"),
            "datacenter": values.get("datacenter")
        }

    return inventory


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--list":
        print(json.dumps(get_inventory(), indent=2))
    elif len(sys.argv) == 3 and sys.argv[1] == "--host":
        inventory = get_inventory()
        host = sys.argv[2]
        hostvars = inventory.get("_meta", {}).get("hostvars", {}).get(host, {})
        print(json.dumps(hostvars, indent=2))
    else:
        print(json.dumps(get_inventory(), indent=2))


if __name__ == "__main__":
    main()
