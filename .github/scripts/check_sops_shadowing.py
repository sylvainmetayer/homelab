#!/usr/bin/env python3
"""Fail when a key of ansible/secrets.sops.yaml bears the name of a variable
that a playbook, a shared task file or a role sets in a layer it outranks.

community.sops.load_vars (return_method: vars-only, ansible-core 2.21+) puts
the secrets in the include_vars layer: they beat play `vars:`, the `vars:` of a
`roles:` entry, block and task `vars:` (import_role's included) and a role's
vars/*.yml, and the override silently loses (AGENTS.md, "Secrets"). Not
checked, because they outrank the secrets: set_fact/register, role params (bare
keys of a `roles:` entry) and the `vars:` of an include_role.

The key names of a SOPS file are plaintext, so no Age key is needed. The keys
of ansible/molecule/_shared/vars/fake_secrets.yml are checked too: Molecule
loads them in the same layer.

Usage (from the repository root): check_sops_shadowing.py
"""

import glob
import sys

import yaml

SOPS_FILES = [
    "ansible/secrets.sops.yaml",
    "ansible/molecule/_shared/vars/fake_secrets.yml",
]
# Playbooks, shared task files, role tasks/handlers: every `vars:` mapping in
# them, at any depth (play, roles: entry, block, task).
VARS_KEYWORD_FILES = [
    "ansible/*.yml",
    "ansible/*.yaml",
    "ansible/tasks/*.yml",
    "ansible/roles/*/tasks/**/*.yml",
    "ansible/roles/*/handlers/**/*.yml",
]
# Files whose top-level keys are variables.
VARS_FILES = ["ansible/roles/*/vars/**/*.yml", "ansible/roles/*/vars/**/*.yaml"]

INCLUDE_ROLE = {"include_role", "ansible.builtin.include_role"}


class Loader(yaml.SafeLoader):
    """SafeLoader that tolerates Ansible's custom tags (!vault, !unsafe)."""


Loader.add_multi_constructor("!", lambda loader, suffix, node: None)


def load(path):
    with open(path, encoding="utf-8") as f:
        return yaml.load(f, Loader=Loader)  # noqa: S506 - SafeLoader subclass


def sops_key_names():
    names = {}
    for path in SOPS_FILES:
        for key in load(path) or {}:
            if key != "sops":
                names.setdefault(key, path)
    return names


def walk(node, where, found):
    """Collect (variable, location) for every `vars:` mapping under node."""
    if isinstance(node, dict):
        is_include_role = any(k in node for k in INCLUDE_ROLE)
        for key, value in node.items():
            if key == "vars" and isinstance(value, dict) and not is_include_role:
                label = (
                    node.get("name")
                    or node.get("role")
                    or node.get("hosts")
                    or next((k for k in node if k != "vars"), "?")
                )
                for var in value:
                    found.append((var, f"{where} ({label})"))
            walk(value, where, found)
    elif isinstance(node, list):
        for item in node:
            walk(item, where, found)


def main():
    sops_names = sops_key_names()
    found = []
    for pattern in VARS_KEYWORD_FILES:
        for path in sorted(glob.glob(pattern, recursive=True)):
            if path.endswith("secrets.sops.yaml"):
                continue
            walk(load(path), path, found)
    for pattern in VARS_FILES:
        for path in sorted(glob.glob(pattern, recursive=True)):
            for var in load(path) or {}:
                found.append((var, path))

    collisions = sorted({(var, where) for var, where in found if var in sops_names})
    if not collisions:
        print(f"OK: none of the {len(sops_names)} SOPS keys is set by a vars: it would shadow.")
        return 0
    for var, where in collisions:
        print(
            f"::error::SOPS key '{var}' ({sops_names[var]}) shadows the variable set in {where}: "
            "the secret wins over it (include_vars layer). Rename the key in sops "
            "(per instance: prod_planning_*, demo_planning_*) and hand it over through vars:."
        )
    return 1


if __name__ == "__main__":
    sys.exit(main())
