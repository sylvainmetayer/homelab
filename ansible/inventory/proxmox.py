#!/usr/bin/env python3
"""
Dynamic inventory script for Proxmox VMs managed by OpenTofu.
Reads terraform state to generate Ansible inventory.

Address resolution, in order of preference:

1. The address declared in the VM's cloud-init `ip_config`, when it is a
   static CIDR. This is what the configuration asks for, so it does not go
   stale the way the observed value does.
2. Otherwise the first address reported by the guest agent that falls inside
   LAN_CIDR. Picking by subnet rather than by list position matters: the
   docker host exposes a dozen container bridges (172.x) alongside its real
   NIC, and their order is not stable.

Note that both come from `tofu show -json`, i.e. from the *state*. If the
state has not been refreshed since the VM's address changed, the value here
is whatever the last apply/refresh recorded. A host that resolves to an
address that no longer answers usually means the state is stale - run
`tofu -chdir=tofu/proxmox apply -refresh-only` rather than hardcoding an
address here.

Environment:
  PROXMOX_TOFU_DIR   override the OpenTofu directory to read
  PROXMOX_LAN_CIDR   override the LAN subnet (default 192.168.0.0/16)
"""

import ipaddress
import json
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
TOFU_DIR = Path(os.environ.get("PROXMOX_TOFU_DIR", REPO_ROOT / "tofu" / "proxmox"))
LAN_CIDR = ipaddress.ip_network(os.environ.get("PROXMOX_LAN_CIDR", "192.168.0.0/16"))

VM_TYPES = (
    "proxmox_virtual_environment_vm",
    "proxmox_virtual_environment_container",
)


def warn(message):
    """Report a problem without pretending the inventory is simply empty."""
    print(f"proxmox.py: {message}", file=sys.stderr)


def get_tofu_state():
    """Get terraform state from tofu, or None if it cannot be read."""
    if not TOFU_DIR.is_dir():
        warn(f"OpenTofu directory not found: {TOFU_DIR}")
        return None
    try:
        result = subprocess.run(
            ["tofu", "show", "-json"],
            cwd=TOFU_DIR,
            capture_output=True,
            text=True,
            check=True,
        )
    except FileNotFoundError:
        warn("`tofu` executable not found in PATH")
        return None
    except subprocess.CalledProcessError as exc:
        warn(f"`tofu show -json` failed in {TOFU_DIR}: {exc.stderr.strip()}")
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        warn(f"could not parse `tofu show -json` output: {exc}")
        return None


def _first(value):
    """Unwrap the single-element lists the provider uses for nested blocks."""
    if isinstance(value, list):
        return value[0] if value else None
    return value


def configured_address(values):
    """Static address from cloud-init ip_config, or None if DHCP/absent."""
    ip_config = _first(_first(values.get("initialization")) or {})
    if not isinstance(ip_config, dict):
        return None
    ipv4 = _first((_first(ip_config.get("ip_config")) or {}).get("ipv4"))
    if not isinstance(ipv4, dict):
        return None
    address = ipv4.get("address")
    if not address or address == "dhcp":
        return None
    try:
        return str(ipaddress.ip_interface(address).ip)
    except ValueError:
        warn(f"unparseable ip_config address: {address!r}")
        return None


def observed_address(values):
    """First guest-agent address inside LAN_CIDR, ignoring bridges/loopback."""
    for addresses in values.get("ipv4_addresses") or []:
        for address in addresses or []:
            try:
                parsed = ipaddress.ip_address(address)
            except ValueError:
                continue
            if parsed in LAN_CIDR:
                return address
    return None


def get_inventory():
    """Generate Ansible inventory from tofu state."""
    inventory = {
        "_meta": {"hostvars": {}},
        "all": {"children": ["proxmox"]},
        "proxmox": {"hosts": []},
    }

    state = get_tofu_state()
    if not state:
        return inventory

    resources = state.get("values", {}).get("root_module", {}).get("resources", [])

    for resource in resources:
        if resource.get("type") not in VM_TYPES:
            continue

        values = resource.get("values") or {}
        name = values.get("name")
        if not name:
            continue

        ip = configured_address(values) or observed_address(values)
        if not ip:
            warn(f"no address in {LAN_CIDR} for {name!r}, skipping")
            continue

        inventory["proxmox"]["hosts"].append(name)
        inventory["_meta"]["hostvars"][name] = {
            "ansible_host": ip,
            "vm_id": values.get("vm_id"),
            "node_name": values.get("node_name"),
        }

    if not inventory["proxmox"]["hosts"]:
        warn("no usable hosts found in the OpenTofu state")

    return inventory


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--host":
        inventory = get_inventory()
        print(json.dumps(inventory["_meta"]["hostvars"].get(sys.argv[2], {}), indent=2))
    else:
        print(json.dumps(get_inventory(), indent=2))


if __name__ == "__main__":
    main()
