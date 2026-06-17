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
        },
        "proxmox_apps": {
            "hosts": []
        }
    }

    state = get_tofu_state()
    if not state:
        return inventory

    resources = state.get("values", {}).get("root_module", {}).get("resources", [])

    for resource in resources:
        resource_type = resource.get("type")
        if resource_type not in ["proxmox_virtual_environment_vm", "proxmox_virtual_environment_container"]:
            continue

        values = resource.get("values", {})
        host = extract_host_name(resource, values)
        ip = extract_ipv4(values)
        if not host or not ip or ip == "127.0.0.1":
            continue

        inventory["proxmox"]["hosts"].append(host)
        inventory["_meta"]["hostvars"][host] = {
            "ansible_host": ip,
            "vm_id": values.get("vm_id"),
            "node_name": values.get("node_name")
        }

        role_name = extract_role(values)
        if role_name:
            if role_name not in inventory:
                inventory[role_name] = {"hosts": []}
                if role_name not in inventory["all"]["children"]:
                    inventory["all"]["children"].append(role_name)
            inventory[role_name]["hosts"].append(host)
            inventory["proxmox_apps"]["hosts"].append(host)

    inventory["proxmox"]["hosts"] = sorted(set(inventory["proxmox"]["hosts"]))
    inventory["proxmox_apps"]["hosts"] = sorted(set(inventory["proxmox_apps"]["hosts"]))

    return inventory


def extract_host_name(resource, values):
    """Resolve host name from resource values."""
    if values.get("name"):
        return values["name"]

    initialization = values.get("initialization", [])
    if initialization and initialization[0].get("hostname"):
        return initialization[0].get("hostname")

    if resource.get("index") is not None:
        return str(resource["index"])

    vm_id = values.get("vm_id")
    if vm_id is not None:
        return f"vm-{vm_id}"

    return None


def extract_ipv4(values):
    """Extract IPv4 from container or VM values."""
    ipv4 = values.get("ipv4")
    if isinstance(ipv4, str) and ipv4:
        return ipv4.split("/")[0]

    ipv4_addresses = values.get("ipv4_addresses", [])
    if len(ipv4_addresses) > 1 and ipv4_addresses[1]:
        return ipv4_addresses[1][0]
    if len(ipv4_addresses) > 0 and ipv4_addresses[0]:
        return ipv4_addresses[0][0]

    initialization = values.get("initialization", [])
    if initialization:
        ip_config = initialization[0].get("ip_config", [])
        if ip_config:
            ipv4_init = ip_config[0].get("ipv4", [])
            if ipv4_init and ipv4_init[0].get("address"):
                return ipv4_init[0]["address"].split("/")[0]

    return None


def extract_role(values):
    """Extract app role from tags formatted as role:<name>."""
    tags = values.get("tags", [])
    if isinstance(tags, str):
        tags = tags.replace(";", ",")
        tags = [tag.strip() for tag in tags.split(",") if tag.strip()]
    for tag in tags:
        if tag.startswith("role:"):
            return tag.split(":", 1)[1]
    return None

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
