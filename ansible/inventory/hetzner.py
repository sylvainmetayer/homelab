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

Environment:
  HETZNER_BASTION   name of the server to jump through (default: pangolin)
"""

import json
import os
import subprocess
import sys

BASTION = os.environ.get("HETZNER_BASTION", "pangolin")


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
    except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError):
        return None


def get_inventory():
    """Generate Ansible inventory from tofu state."""
    inventory = {
        "_meta": {
            "hostvars": {}
        },
        "all": {
            "children": ["hetzner"]
        },
        "hetzner": {
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

            if ipv4_address and ipv4_address != "127.0.0.1":
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
        inventory["hetzner"]["hosts"].append(name)
        inventory["_meta"]["hostvars"][name] = {
            "ansible_host": private_ip,
            "ansible_user": "sylvain",
            "ansible_ssh_common_args": f"-o ProxyJump=sylvain@{bastion}",
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
