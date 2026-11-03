#!/usr/bin/env python3
"""Every compose service sets no-new-privileges, or is a listed exception.

docs/conventions/container-hardening.md: the option is the default, and Molecule
starts no image, so a service that loses it (or a new one born without it) would
go unnoticed. This check (Lint workflow) fails on such a service, on an exception
whose service is gone and on one that now sets the option: the list only says
what is true.

The templates are Jinja, so they are not loaded as YAML: an `{% if %}` or a `{{ }}`
breaks a parser or, rendered, hides a service behind a variable (flip_planning's
Keycloak). Lines are read as trivy_images.py reads them: a key indented by two
spaces under the top-level `services:` starts a service, whatever Jinja surrounds
it. An option written inside an `{% if %}` counts as set.

Usage (from the repository root, workflow Lint): check_container_hardening.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SERVICE_LINE = re.compile(r"^  (?P<key>[A-Za-z0-9._-]+):\s*(?:#.*)?$")
# Block form (`- no-new-privileges:true`) or flow form (`["no-new-privileges:true"]`).
OPTION = re.compile(r"""(?:^\s*-\s*|[\[,]\s*)["']?no-new-privileges:true\b""")

# Owner (role, or compose/ directory; Immich's two share a name) -> why it is left
# out, and its services. The reasons are detailed in the doctrine.
EXCEPTIONS = {
    "borgmatic": (
        "NAS, nas.yml lancé à la main, pas encore essayé",
        ["borgmatic"],
    ),
    "flip_planning": (
        "production, non analysé",
        ["app", "postgres", "mailpit", "assets", "keycloak", "keycloak-db", "pgadmin"],
    ),
    "immich": (
        "service familial, non analysé",
        [
            "immich-server",
            "immich-server-remote",
            "immich-machine-learning",
            "redis",
            "database",
            "immich-swipe",
            "immich-selfie-timelapse",
        ],
    ),
    "monica_v4": ("gelée jusqu'à la version de décembre 2026", ["crm", "monica_v4_db"]),
    "newt": ("chemin d'accès à tout le reste, non analysé", ["newt"]),
    "pangolin": (
        "chemin d'accès à tout le reste, non analysé",
        ["pangolin", "gerbil", "traefik", "crowdsec"],
    ),
    "paperless_ngx": (
        "en pause",
        ["broker", "db", "webserver", "gotenberg", "tika"],
    ),
}


def compose_files(root):
    yield from sorted(root.glob("ansible/roles/*/templates/compose.yaml*"))
    yield from sorted(root.glob("compose/*/compose.yaml"))


def owner(root, path):
    parts = path.relative_to(root).parts
    return parts[2] if parts[:2] == ("ansible", "roles") else parts[1]


def services(text):
    """{service: has the option} of a compose template."""
    found = {}
    current = None
    in_services = False
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("{%"):
            continue
        if not line.startswith(" "):
            in_services = line.rstrip() == "services:"
            current = None
            continue
        if not in_services:
            continue
        key = SERVICE_LINE.match(line)
        if key:
            current = key["key"]
            found.setdefault(current, False)
        elif current and OPTION.search(line):
            found[current] = True
    return found


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
        f"{name}/{service} : dans EXCEPTIONS, absent des composes."
        for name, (_, listed) in sorted(exceptions.items())
        for service in sorted(listed)
        if (name, service) not in found
    )
    return errors


def main():
    found = {}
    for path in compose_files(ROOT):
        name = owner(ROOT, path)
        for service, hardened in services(path.read_text(encoding="utf-8")).items():
            # Same service in two files of one owner: each must have the option.
            found[(name, service)] = hardened and found.get((name, service), True)
    errors = check(found, EXCEPTIONS)
    for error in errors:
        print(error)
    if not errors:
        print(f"{len(found)} services : no-new-privileges partout hors exceptions.")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
