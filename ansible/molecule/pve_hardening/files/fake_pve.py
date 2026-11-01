#!/usr/bin/python3
"""Faux pvesh et pve-firewall du scénario pve_hardening.

pvesh : la partie SDN de l'API (zones, vnets, sous-réseaux) sur un état JSON
(/var/lib/fake-pve/sdn.json), chaque appel qui modifie journalisé dans
/var/lib/fake-pve/calls.log. Comme la vraie API, supprimer un objet qui en
contient encore un autre échoue.
pve-firewall status : « enabled/running » si /etc/pve/firewall/cluster.fw
porte enable: 1, « disabled/running » sinon.
"""
import json
import os
import re
import sys

STATE = "/var/lib/fake-pve/sdn.json"
LOG = "/var/lib/fake-pve/calls.log"


def load():
    with open(STATE, encoding="utf-8") as handle:
        return json.load(handle)


def save(state):
    with open(STATE, "w", encoding="utf-8") as handle:
        json.dump(state, handle)


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(255)


def pvesh_get(path, state):
    if path == "/cluster/sdn/zones":
        return [{"zone": z, "type": "simple"} for z in state["zones"]]
    if path == "/cluster/sdn/vnets":
        return [{"vnet": v, "zone": z} for v, z in state["vnets"].items()]
    match = re.fullmatch(r"/cluster/sdn/vnets/([^/]+)/subnets", path)
    if not match:
        fail(f"unsupported get {path}")
    vnet = match.group(1)
    if vnet not in state["vnets"]:
        fail(f"vnet {vnet} does not exist")
    return [{"subnet": s, "vnet": v} for s, v in state["subnets"].items() if v == vnet]


def delete_subnet(state, vnet, subnet):
    if state["subnets"].get(subnet) != vnet:
        fail(f"subnet {subnet} does not exist")
    del state["subnets"][subnet]


def delete_vnet(state, vnet):
    if vnet not in state["vnets"]:
        fail(f"vnet {vnet} does not exist")
    if vnet in state["subnets"].values():
        fail(f"vnet {vnet} still has subnets")
    del state["vnets"][vnet]


def delete_zone(state, zone):
    if zone not in state["zones"]:
        fail(f"zone {zone} does not exist")
    if zone in state["vnets"].values():
        fail(f"zone {zone} still has vnets")
    state["zones"].remove(zone)


DELETES = [
    (r"/cluster/sdn/vnets/([^/]+)/subnets/([^/]+)", delete_subnet),
    (r"/cluster/sdn/vnets/([^/]+)", delete_vnet),
    (r"/cluster/sdn/zones/([^/]+)", delete_zone),
]


def pvesh(args):
    # Les options (--output-format, --running) ne changent rien ici.
    method, path = args[0], args[1]
    state = load()
    if method == "get":
        print(json.dumps(pvesh_get(path, state)))
        return
    with open(LOG, "a", encoding="utf-8") as log:
        log.write(f"{method} {path}\n")
    if method == "set" and path == "/cluster/sdn":
        return
    if method != "delete":
        fail(f"unsupported {method} {path}")
    for pattern, handler in DELETES:
        match = re.fullmatch(pattern, path)
        if match:
            handler(state, *match.groups())
            save(state)
            return
    fail(f"unsupported delete {path}")


def pve_firewall(args):
    if args != ["status"]:
        fail(f"unsupported pve-firewall {args}")
    try:
        with open("/etc/pve/firewall/cluster.fw", encoding="utf-8") as handle:
            enabled = re.search(r"^enable: 1$", handle.read(), re.MULTILINE)
    except FileNotFoundError:
        enabled = None
    print(f"Status: {'enabled' if enabled else 'disabled'}/running")


if __name__ == "__main__":
    command = os.path.basename(sys.argv[0])
    if command == "pvesh":
        pvesh(sys.argv[1:])
    elif command == "pve-firewall":
        pve_firewall(sys.argv[1:])
    else:
        fail(f"unknown command {command}")
