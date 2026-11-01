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


def pvesh(args):
    method, path = args[0], args[1]
    state = load()
    if method == "get":
        if path == "/cluster/sdn/zones":
            print(json.dumps([{"zone": z, "type": "simple"} for z in state["zones"]]))
            return
        if path == "/cluster/sdn/vnets":
            print(json.dumps([{"vnet": v, "zone": z} for v, z in state["vnets"].items()]))
            return
        match = re.fullmatch(r"/cluster/sdn/vnets/([^/]+)/subnets", path)
        if match:
            vnet = match.group(1)
            if vnet not in state["vnets"]:
                fail(f"vnet {vnet} does not exist")
            print(json.dumps([{"subnet": s, "vnet": v} for s, v in state["subnets"].items() if v == vnet]))
            return
        fail(f"unsupported get {path}")
    with open(LOG, "a", encoding="utf-8") as log:
        log.write(f"{method} {path}\n")
    if method == "set" and path == "/cluster/sdn":
        return
    if method != "delete":
        fail(f"unsupported {method} {path}")
    match = re.fullmatch(r"/cluster/sdn/vnets/([^/]+)/subnets/([^/]+)", path)
    if match:
        if state["subnets"].get(match.group(2)) != match.group(1):
            fail(f"subnet {match.group(2)} does not exist")
        del state["subnets"][match.group(2)]
    elif match := re.fullmatch(r"/cluster/sdn/vnets/([^/]+)", path):
        vnet = match.group(1)
        if vnet not in state["vnets"]:
            fail(f"vnet {vnet} does not exist")
        if vnet in state["subnets"].values():
            fail(f"vnet {vnet} still has subnets")
        del state["vnets"][vnet]
    elif match := re.fullmatch(r"/cluster/sdn/zones/([^/]+)", path):
        zone = match.group(1)
        if zone not in state["zones"]:
            fail(f"zone {zone} does not exist")
        if zone in state["vnets"].values():
            fail(f"zone {zone} still has vnets")
        state["zones"].remove(zone)
    else:
        fail(f"unsupported delete {path}")
    save(state)


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
