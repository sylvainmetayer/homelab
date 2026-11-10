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


def main():
    found, unread = scan(ROOT)
    errors = [f"{path} : aucun service lu sous `services:`." for path in unread]
    errors.extend(check(found, EXCEPTIONS))
    for error in errors:
        print(error)
    if not errors:
        print(f"{len(found)} services : no-new-privileges partout hors exceptions.")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
