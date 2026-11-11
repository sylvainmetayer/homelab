#!/usr/bin/env python3
"""Every compose service sets no-new-privileges, or is a listed exception, and
every risky privilege (docker.sock mount, privileged, host namespace, device,
cap_add outside Docker's default set, unconfined profile) is listed with its reason.

docs/conventions/container-hardening.md: the option is the default, and Molecule
starts no image, so a service that loses it (or a new one born without it) would
go unnoticed. This check (Lint workflow) fails on such a service, on an exception
whose service is gone and on one that now sets the option: the list only says
what is true.

The templates are Jinja, so they are not loaded as YAML: an `{% if %}` or a `{{ }}`
breaks a parser or, rendered, hides a service behind a variable (flip_planning's
Keycloak). Lines are read as trivy_images.py reads them: a key indented by two
spaces under the top-level `services:` starts a service, whatever Jinja surrounds
it. An option written inside an `{% if %}` counts as set, in the service's own
`security_opt` only. A compose where no service is read fails too: its layout has
left what this parser knows, and it would otherwise pass unchecked.

Usage (from the repository root, workflow Lint): check_container_hardening.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# Only a key closes a top-level section: `---` and Jinja also sit in column 0.
TOP_LEVEL = re.compile(r"^(?P<key>[A-Za-z0-9._-]+):")
# The name may be templated, and an anchor or a flow value may follow it.
SERVICE_LINE = re.compile(r"^  (?P<key>(?:\{\{[^{}]*\}\}|[A-Za-z0-9._-])+):(?:\s|$)")
SERVICE_KEY = re.compile(r"^    (?P<key>[A-Za-z_]+):")
# Block form (`- no-new-privileges:true`) or flow form (`["no-new-privileges:true"]`).
OPTION = re.compile(
    r"""^\s*(?:-\s*|security_opt:\s*\[[^\]#]*)["']?no-new-privileges:true\b"""
)

# Owner (role, or compose/ directory) -> why it is left
# out, and its services. The reasons are detailed in the doctrine.
EXCEPTIONS = {
    "monica_v4": ("gelée jusqu'à la version de décembre 2026", ["crm", "monica_v4_db"]),
    "pangolin": (
        "chemin d'accès à tout le reste, non analysé",
        ["pangolin", "gerbil", "traefik", "crowdsec"],
    ),
}

# (owner, service) -> {risky feature: reason}. Every feature `features()` reads
# in a compose must be here, and every entry must still be there: a new mount of
# docker.sock, privilege, device or host namespace is a decision, taken in this
# list. The reasons are detailed in the doctrine (Docker Bench table).
ALLOWED = {
    ("beszel_agent", "agent"): {
        "cap_add: SYS_RAWIO": "lecture S.M.A.R.T. des disques",
        "device: {{ device.path }}": "disques lus par smartctl (boucle sur les périphériques de l'hôte)",
        "network_mode: host": "statistiques des interfaces réseau de l'hôte",
    },
    ("beszel_agent", "socket-proxy"): {"docker.sock": "le proxy de socket : API filtrée en lecture seule"},
    ("borgmatic", "borgmatic"): {"pid: host": "verrous de borg : PID et id d'hôte de l'hôte, comme un borg installé dessus"},
    ("immich_ml", "immich-machine-learning"): {"device: /dev/dri": "accélération GPU (OpenVINO)"},
    ("jellyfin", "jellyfin"): {"device: {{ jellyfin_render_device }}": "transcodage matériel (rendu GPU)"},
    ("log_agent", "agent"): {"network_mode: host": "lit le journal et le réseau de l'hôte"},
    ("log_agent", "socket-proxy"): {"docker.sock": "le proxy de socket : API filtrée en lecture seule"},
    ("mediamanager", "gluetun"): {
        "cap_add: NET_ADMIN": "tunnel VPN et son pare-feu",
        "device: /dev/net/tun": "interface du tunnel",
    },
    ("nas_proxy", "forward"): {"network_mode: host": "relais Traefik du NAS sur le réseau de l'hôte (nas_proxy)"},
    ("newt", "socket-proxy"): {"docker.sock": "le proxy de socket : API filtrée en lecture seule"},
    ("pangolin", "gerbil"): {"cap_add: NET_ADMIN": "interface WireGuard, exigence amont"},
}


# What Docker grants a container without cap_add (moby's default set): a
# cap_add of one of these changes nothing, any other one is listed below.
DEFAULT_CAPS = {
    "AUDIT_WRITE", "CHOWN", "DAC_OVERRIDE", "FOWNER", "FSETID", "KILL", "MKNOD",
    "NET_BIND_SERVICE", "NET_RAW", "SETFCAP", "SETGID", "SETPCAP", "SETUID", "SYS_CHROOT",
}
# `key: host` of a service: shares a namespace of the host.
HOST_NAMESPACES = ("network_mode", "pid", "ipc", "userns_mode", "uts")
LIST_ITEM = re.compile(r"""^      - \s*["']?(?P<value>[^"'#]*?)["']?\s*(?:#.*)?$""")
FLOW_LIST = re.compile(r"^    (?P<key>cap_add|devices|volumes|security_opt):\s*\[(?P<items>[^\]#]*)\]")
UNCONFINED = re.compile(r"^(?:apparmor|seccomp)[=:]unconfined$")


def feature_of(key, value):
    """The risky feature a list item of a service stands for, or None."""
    if key == "cap_add":
        return None if value.removeprefix("CAP_") in DEFAULT_CAPS else f"cap_add: {value}"
    if key == "devices":
        return f"device: {value.split(':')[0]}"
    if key == "volumes":
        return "docker.sock" if "docker.sock" in value.split(":")[0] else None
    return f"security_opt: {value}" if UNCONFINED.match(value) else None


def features(text):
    """[(service, set of risky features)] of a compose template, read like
    services(): `privileged`, a namespace of the host, a `device:` path, a
    `cap_add:` outside Docker's default set, a mount of `docker.sock`, an
    unconfined AppArmor or seccomp profile. A Jinja value is kept as written, so
    that it matches no listed feature and fails."""
    found = []
    in_services = False
    key = ""
    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        if top := TOP_LEVEL.match(line):
            in_services = top["key"] == "services"
            continue
        if not in_services:
            continue
        if service := SERVICE_LINE.match(line):
            found.append((service["key"], set()))
            key = ""
        elif found:
            risky = found[-1][1]
            if match := SERVICE_KEY.match(line):
                key = match["key"]
                value = line.split(":", 1)[1].split("#")[0].strip().strip("\"'")
                if key == "privileged" and value != "false":
                    risky.add("privileged")
                if key in HOST_NAMESPACES and value == "host":
                    risky.add(f"{key}: host")
                if flow := FLOW_LIST.match(line):
                    for item in flow["items"].split(","):
                        if item := item.strip().strip("\"'"):
                            if feature := feature_of(flow["key"], item):
                                risky.add(feature)
            elif (item := LIST_ITEM.match(line)) and key in ("cap_add", "devices", "volumes", "security_opt"):
                if feature := feature_of(key, item["value"]):
                    risky.add(feature)
    return found


def compose_files(root):
    yield from sorted(root.glob("ansible/roles/*/templates/compose.yaml*"))
    yield from sorted(root.glob("compose/*/compose.yaml"))


def owner(root, path):
    parts = path.relative_to(root).parts
    return parts[2] if parts[:2] == ("ansible", "roles") else parts[1]


def services(text):
    """[(service, has the option)] of a compose template, one per occurrence."""
    found = []
    in_services = in_security_opt = False
    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        if top := TOP_LEVEL.match(line):
            in_services = top["key"] == "services"
            continue
        if not in_services:
            continue
        if service := SERVICE_LINE.match(line):
            found.append((service["key"], False))
            in_security_opt = False
        elif found:
            if key := SERVICE_KEY.match(line):
                in_security_opt = key["key"] == "security_opt"
            if in_security_opt and OPTION.match(line):
                found[-1] = (found[-1][0], True)
    return found


def scan(root):
    """({(owner, service): has the option}, the files where no service was read).

    A service read twice (two Jinja branches, two files of one owner) must have
    the option each time.
    """
    found = {}
    unread = []
    for path in compose_files(root):
        name = owner(root, path)
        read = services(path.read_text(encoding="utf-8"))
        if not read:
            unread.append(path.relative_to(root))
        for service, hardened in read:
            found[(name, service)] = hardened and found.get((name, service), True)
    return found, unread


def check(found, exceptions):
    """Errors: found is {(owner, service): has the option}."""
    errors = []
    for (name, service), hardened in sorted(found.items()):
        listed = service in exceptions.get(name, ("", []))[1]
        if not hardened and not listed:
            errors.append(
                f"{name}/{service} : pas de no-new-privileges. L'ajouter "
                "(docs/conventions/container-hardening.md), ou lister le service "
                "avec sa raison dans EXCEPTIONS."
            )
        if hardened and listed:
            errors.append(
                f"{name}/{service} a no-new-privileges : le retirer d'EXCEPTIONS."
            )
    errors.extend(
        f"{name} : exception sans raison dans EXCEPTIONS."
        for name, (reason, _) in sorted(exceptions.items())
        if not reason.strip()
    )
    errors.extend(
        f"{name}/{service} : dans EXCEPTIONS, absent des composes."
        for name, (_, listed) in sorted(exceptions.items())
        for service in sorted(listed)
        if (name, service) not in found
    )
    return errors


def scan_features(root):
    """{(owner, service): risky features}, the branches of a template merged."""
    found = {}
    for path in compose_files(root):
        name = owner(root, path)
        for service, risky in features(path.read_text(encoding="utf-8")):
            found.setdefault((name, service), set()).update(risky)
    return found


def check_features(found, allowed):
    """Errors: found is {(owner, service): risky features}."""
    errors = []
    for (name, service), risky in sorted(found.items()):
        listed = allowed.get((name, service), {})
        errors.extend(
            f"{name}/{service} : {feature} non listé. Le retirer, ou le lister "
            "avec sa raison dans ALLOWED (docs/conventions/container-hardening.md)."
            for feature in sorted(risky - listed.keys())
        )
    for (name, service), listed in sorted(allowed.items()):
        errors.extend(
            f"{name}/{service} : {feature} dans ALLOWED, absent du compose."
            for feature in sorted(listed.keys() - found.get((name, service), set()))
        )
        errors.extend(
            f"{name}/{service} : {feature} sans raison dans ALLOWED."
            for feature, reason in sorted(listed.items())
            if not reason.strip()
        )
    return errors


def main():
    found, unread = scan(ROOT)
    errors = [f"{path} : aucun service lu sous `services:`." for path in unread]
    errors.extend(check(found, EXCEPTIONS))
    errors.extend(check_features(scan_features(ROOT), ALLOWED))
    for error in errors:
        print(error)
    if not errors:
        print(f"{len(found)} services : no-new-privileges partout hors exceptions, privilèges listés.")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
