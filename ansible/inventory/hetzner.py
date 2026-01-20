#!/usr/bin/env python3
"""
Dynamic inventory script for Hetzner Cloud servers managed by OpenTofu.
Reads terraform state to generate Ansible inventory.
"""

import json
import subprocess
import sys


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

    for resource in resources:
        resource_type = resource.get("type")
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
