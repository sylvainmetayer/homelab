#!/usr/bin/env python3
"""
Dynamic inventory script for Proxmox VMs managed by OpenTofu.
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
            cwd="../tofu/proxmox",
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
            "children": ["proxmox"]
        },
        "proxmox": {
            "hosts": []
        }
    }

    state = get_tofu_state()
    if not state:
        return inventory

    resources = state.get("values", {}).get("root_module", {}).get("resources", [])

    for resource in resources:
        resource_type = resource.get("type")
        if resource_type in ["proxmox_virtual_environment_vm", "proxmox_virtual_environment_container"]:
            values = resource.get("values", {})
            name = values.get("name", "unknown")

            # Get IP from ipv4_addresses (index 1 is usually the main interface)
            ipv4_addresses = values.get("ipv4_addresses", [])
            ip = None
            if len(ipv4_addresses) > 1 and ipv4_addresses[1]:
                ip = ipv4_addresses[1][0]
            elif len(ipv4_addresses) > 0 and ipv4_addresses[0]:
                ip = ipv4_addresses[0][0]

            if ip and ip != "127.0.0.1":
                inventory["proxmox"]["hosts"].append(name)
                inventory["_meta"]["hostvars"][name] = {
                    "ansible_host": ip,
                    "vm_id": values.get("vm_id"),
                    "node_name": values.get("node_name")
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
