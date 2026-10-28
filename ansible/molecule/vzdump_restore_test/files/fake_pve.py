#!/usr/bin/python3
"""Faux Proxmox pour le scénario Molecule vzdump_restore_test.

Installé sous /usr/local/sbin avec un lien par commande (pvesh, pvesm, pct,
qm, vma, zstd) : le nom d'appel choisit la commande. L'état (invités,
volumes, sauvegardes, storages) est un JSON que chaque cas du verify écrit ;
chaque appel est journalisé, une ligne JSON par appel. Une commande qui
modifie un invité hors de 900-999 est refusée et journalisée comme
violation : le verify n'en accepte aucune.
"""

import json
import os
import shutil
import sys
import time

# FAKE_PVE_DIR : pour rejouer le scénario hors de Molecule, sur un poste.
BASE = os.environ.get("FAKE_PVE_DIR", "/var/lib/fake-pve")
STATE = f"{BASE}/state.json"
CALLS = f"{BASE}/calls.jsonl"
ROOTFS = f"{BASE}/rootfs"


def load():
    with open(STATE, encoding="utf-8") as handle:
        return json.load(handle)


def save(state):
    with open(STATE, "w", encoding="utf-8") as handle:
        json.dump(state, handle, indent=2)


def log(entry):
    with open(CALLS, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry) + "\n")


def fail(message, code=255):
    print(message, file=sys.stderr)
    sys.exit(code)


def options(args):
    """--clé valeur… en dictionnaire (une valeur par clé)."""
    result = {}
    for index in range(0, len(args) - 1, 2):
        if not args[index].startswith("--"):
            fail(f"argument inattendu : {args[index]}", 2)
        result[args[index][2:]] = args[index + 1]
    return result


def parse_conf(text):
    conf = {}
    for line in text.splitlines():
        if ": " in line and not line.startswith("#"):
            key, value = line.split(": ", 1)
            conf[key] = value
    return conf


def guest(state, vmid, kind=None):
    entry = state["guests"].get(str(vmid))
    if entry is None or (kind and entry["kind"] != kind):
        fail(f"Configuration file 'nodes/molecule/{kind or 'lxc'}/{vmid}.conf' does not exist", 2)
    return entry


def backup(state, volid):
    for item in state["backups"]:
        if item["volid"] == volid:
            return item
    fail(f"volume '{volid}' does not exist", 2)
    return None


def pvesh(state, args):
    if args[:1] != ["get"]:
        fail("seul pvesh get est simulé", 2)
    path, params = args[1], options([a for a in args[2:] if a != ""])
    parts = path.strip("/").split("/")
    if path == "/cluster/resources":
        result = [
            {"vmid": int(vmid), "type": entry["kind"], "status": entry["status"]}
            for vmid, entry in state["guests"].items()
        ]
    elif len(parts) == 5 and parts[2] == "storage" and parts[4] == "content":
        storage = parts[3]
        if storage == "local-lvm":
            result = [v for v in state["volumes"] if str(v["vmid"]) == params.get("vmid", str(v["vmid"]))]
        else:
            now = time.time()
            result = [
                {
                    "volid": item["volid"],
                    "vmid": item["vmid"],
                    "ctime": int(now - item["age_hours"] * 3600),
                    "size": item["size"],
                    "format": item["format"],
                    "subtype": item["subtype"],
                    "content": "backup",
                }
                for item in state["backups"]
                if item["volid"].startswith(storage + ":") and str(item["vmid"]) == params.get("vmid", str(item["vmid"]))
            ]
    elif len(parts) == 5 and parts[2] == "storage" and parts[4] == "status":
        result = state["storage_status"][parts[3]]
    elif parts[2:] == ["vzdump", "extractconfig"]:
        result = backup(state, params["volume"])["config"]
    elif len(parts) == 5 and parts[2] in ("lxc", "qemu") and parts[4] == "config":
        result = guest(state, parts[3], parts[2])["config"]
    else:
        fail(f"chemin non simulé : {path}", 2)
    print(json.dumps(result))


def create(state, kind, vmid, volid, opts):
    if str(vmid) in state["guests"]:
        fail(f"unable to create {'CT' if kind == 'lxc' else 'VM'} {vmid} - already exists")
    if "force" in opts:
        fail("--force refusé par le faux Proxmox", 98)
    conf = parse_conf(backup(state, volid)["config"])
    for key in ("storage", "unique", "archive"):
        opts.pop(key, None)
    conf.update(opts)
    state["guests"][str(vmid)] = {"kind": kind, "status": "stopped", "config": conf}
    state["volumes"].append({"volid": f"local-lvm:vm-{vmid}-disk-0", "vmid": vmid})
    if kind == "lxc":
        shutil.copytree(state["lxc_rootfs_fixture"], rootfs(vmid), symlinks=True)


def delete_keys(state, entry, opts):
    if not state.get("set_ignores_delete"):
        for key in opts.pop("delete", "").split(","):
            entry["config"].pop(key, None)
    opts.pop("delete", None)
    entry["config"].update(opts)


def destroy(state, vmid, opts):
    entry = guest(state, vmid)
    if entry["status"] == "running":
        fail(f"{vmid} is running")
    if opts.get("destroy-unreferenced-disks") != "0":
        fail("destroy sans --destroy-unreferenced-disks 0", 97)
    del state["guests"][str(vmid)]
    state["volumes"] = [v for v in state["volumes"] if str(v["vmid"]) != str(vmid)]
    shutil.rmtree(rootfs(vmid), ignore_errors=True)


def rootfs(vmid):
    # vmid est un int (main) : rien du chemin ne vient de la ligne de commande.
    return os.path.join(ROOTFS, str(int(vmid)))


def pct_mount(state, vmid, _args):
    guest(state, vmid, "lxc")["mounted"] = True
    print(f"mounted CT {vmid} in '{rootfs(vmid)}'")


def pct_unmount(state, vmid, _args):
    if not guest(state, vmid, "lxc").pop("mounted", False):
        fail(f"CT {vmid} is not mounted", 2)


def pct_start(state, vmid, _args):
    entry = guest(state, vmid, "lxc")
    if entry.get("mounted"):
        fail(f"CT {vmid} is locked (mounted)")
    unit = os.path.join(rootfs(vmid), "etc/systemd/system/newt.service")
    masked = ["newt.service"] if os.path.islink(unit) and os.readlink(unit) == "/dev/null" else []
    log({"start": vmid, "masked": masked, "config": entry["config"]})
    entry["status"] = "running"


def pct_exec(state, vmid, args):
    entry = guest(state, vmid, "lxc")
    if entry["status"] != "running":
        fail(f"CT {vmid} not running")
    inner = args[args.index("--") + 1:]
    if inner == ["ls", "-1", "/sys/class/net"]:
        print("\n".join(["lo"] + [f"eth{key[3:]}" for key in entry["config"] if key.startswith("net")]))
    elif "is-system-running" in inner:
        print(state["lxc_system_state"])
        sys.exit(0 if state["lxc_system_state"] == "running" else 1)
    elif "--failed" in inner:
        print(state.get("lxc_failed_units", ""))
    else:
        fail(f"commande non simulée : {inner}", 2)


def set_status(kind, status):
    def handler(state, vmid, _args):
        guest(state, vmid, kind)["status"] = status
    return handler


def print_status(kind):
    def handler(state, vmid, _args):
        print(f"status: {guest(state, vmid, kind)['status']}")
    return handler


def qm_create(state, vmid, args):
    opts = options(args[2:])
    create(state, "qemu", vmid, opts["archive"], opts)


def qm_start(state, vmid, _args):
    entry = guest(state, vmid, "qemu")
    log({"start": vmid, "config": entry["config"]})
    entry["status"] = "running"


def qm_guest(state, vmid, _args):
    sys.exit(0 if guest(state, vmid, "qemu")["status"] == "running" else 2)


HANDLERS = {
    "pct": {
        "restore": lambda state, vmid, args: create(state, "lxc", vmid, args[2], options(args[3:])),
        "set": lambda state, vmid, args: delete_keys(state, guest(state, vmid, "lxc"), options(args[2:])),
        "mount": pct_mount,
        "unmount": pct_unmount,
        "start": pct_start,
        "exec": pct_exec,
        "status": print_status("lxc"),
        "stop": set_status("lxc", "stopped"),
        "destroy": lambda state, vmid, args: destroy(state, vmid, options(args[2:])),
    },
    "qm": {
        "create": qm_create,
        "set": lambda state, vmid, args: delete_keys(state, guest(state, vmid, "qemu"), options(args[2:])),
        "start": qm_start,
        # qm guest cmd <vmid> ping
        "guest": qm_guest,
        "status": print_status("qemu"),
        "stop": set_status("qemu", "stopped"),
        "destroy": lambda state, vmid, args: destroy(state, vmid, options(args[2:])),
    },
}


def target_of(args):
    """L'id visé : `qm guest cmd <vmid> …` le met en troisième position."""
    if args[:2] == ["guest", "cmd"]:
        return args[2] if len(args) > 2 else ""
    return args[1] if len(args) > 1 else ""


def archive_path(state, argument):
    """Le chemin d'une archive connue de l'état, jamais celui de l'argument."""
    for item in state["backups"]:
        if item["path"] == argument:
            return item["path"]
    fail(f"archive inconnue : {argument}", 2)
    return None


def guest_command(state, name, args):
    handler = HANDLERS[name].get(args[0] if args else "")
    if handler is None:
        fail(f"{name} {' '.join(args[:1])} non simulé", 2)
    target = target_of(args)
    if not target.isdigit() or not 900 <= int(target) <= 999:
        log({"violation": [name, *args]})
        fail("le faux Proxmox refuse de toucher un invité hors de 900-999", 99)
    handler(state, int(target), args)


def main():
    name, args = os.path.basename(sys.argv[0]), sys.argv[1:]
    log({"argv": [name, *args]})
    state = load()
    if name == "zstd":
        with open(archive_path(state, args[-1]), "rb") as handle:
            shutil.copyfileobj(handle, sys.stdout.buffer)
        return
    if name == "vma":
        if args[-1] == "-":
            data = sys.stdin.buffer.read()
        else:
            with open(archive_path(state, args[-1]), "rb") as handle:
                data = handle.read()
        if not data.startswith(b"VMA"):
            fail("vma: verify failed - wrong vma extent header", 1)
        return
    if name == "pvesh":
        pvesh(state, args)
    elif name == "pvesm":
        if args[:1] != ["path"]:
            fail("seul pvesm path est simulé", 2)
        print(backup(state, args[1])["path"])
    elif name in HANDLERS:
        guest_command(state, name, args)
    else:
        fail(f"commande non simulée : {name}", 2)
    save(state)


if __name__ == "__main__":
    main()
