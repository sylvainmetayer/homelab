#!/usr/bin/env python3
"""Map changed files to the ansible-playbook --tags needed to redeploy the
affected role(s), for one or more playbooks.

Usage: resolve_docker_tags.py <playbook.yml> [<playbook.yml> ...] < changed-files.txt
Changed file paths are read one per line from stdin.
Prints a JSON object {playbook_path: "tag1,tag2"} to stdout, one entry per
playbook argument (value is "" when nothing changed for that playbook).
"""
import json
import pathlib
import re
import sys
from pathlib import Path

import yaml

GENERIC_TAGS = {"app", "setup"}
ROLE_PATH_RE = re.compile(r"^ansible/roles/([^/]+)/")
# Seuls les playbooks à la racine de ansible/ peuvent être lus : le fichier
# ouvert vient de cette liste, jamais de l'argument (pas de traversée de chemin).
ANSIBLE_DIR = Path(__file__).resolve().parents[2] / "ansible"
PLAYBOOKS = {p.name: p for p in ANSIBLE_DIR.glob("*.y*ml")}


def safe_playbook_path(playbook_path):
    path = Path(playbook_path).resolve()
    known = PLAYBOOKS.get(path.name)
    if known is None or known.resolve() != path:
        sys.exit(f"::error::{playbook_path} is not a playbook of {ANSIBLE_DIR}, refusing to read it")
    return known


def load_role_tags(playbook_path):
    with open(safe_playbook_path(playbook_path)) as f:
        playbook = yaml.safe_load(f)

    # A role can be applied more than once in the same play, one entry per
    # environment (flip_planning: production and demo). Each entry carries its
    # own tag, so the tags ACCUMULATE: assigning here instead would let the
    # last entry shadow the earlier ones, and a change to the role would
    # silently redeploy only the last environment.
    role_tags = {}
    for entry in playbook[0]["roles"]:
        if isinstance(entry, str):
            continue
        role_name = entry.get("role", entry.get("name"))
        # `tags` is either "a,b" or a YAML list ([decommission, never]).
        tags = entry.get("tags", "")
        if isinstance(tags, str):
            tags = tags.split(",")
        known = role_tags.setdefault(role_name, [])
        known.extend(t for t in (str(t).strip() for t in tags) if t and t not in known)
    return role_tags


def changed_roles(changed_files):
    roles = set()
    for path in changed_files:
        match = ROLE_PATH_RE.match(path)
        if match:
            roles.add(match.group(1))
    return roles


def add_dependents(roles, roles_dir=pathlib.Path("ansible/roles")):
    """A role pulled in only through meta/main.yml `dependencies` (nas_storage)
    has no entry, hence no tag, in any playbook: redeploy the roles that
    depend on it instead, since they run it under their own tags.

    Returns the expanded role set and, for each changed role, the roles that
    depend on it (transitively)."""
    dependents = {}
    for meta in roles_dir.glob("*/meta/main.yml"):
        for dep in (yaml.safe_load(meta.read_text()) or {}).get("dependencies") or []:
            name = dep if isinstance(dep, str) else dep.get("role", dep.get("name"))
            dependents.setdefault(name, set()).add(meta.parent.parent.name)

    pulled_by = {}
    for role in roles:
        seen = set()
        pending = [role]
        while pending:
            for dependent in dependents.get(pending.pop(), ()):
                if dependent not in seen:
                    seen.add(dependent)
                    pending.append(dependent)
        pulled_by[role] = seen
    return set(roles).union(*pulled_by.values()), pulled_by


def resolve_tags(role_tags, roles):
    matched = {role: role_tags[role] for role in roles if role in role_tags}

    # A role tagged `never` (decommission_app) only runs when asked for by
    # name: a change to it must not deploy anything.
    all_tags = {tag for tags in matched.values() if "never" not in tags for tag in tags}
    specific = all_tags - GENERIC_TAGS

    resolved = specific if specific else all_tags
    return matched, resolved


def main():
    playbook_paths = sys.argv[1:]
    changed_files = [line.strip() for line in sys.stdin if line.strip()]
    roles, pulled_by = add_dependents(changed_roles(changed_files))

    result = {}
    all_matched_roles = set()
    for playbook_path in playbook_paths:
        role_tags = load_role_tags(playbook_path)
        matched, resolved = resolve_tags(role_tags, roles)
        all_matched_roles |= matched.keys()

        for role, tags in matched.items():
            if "never" in tags:
                print(f"::notice::role '{role}' changed but is tagged never in {playbook_path}, not deployed", file=sys.stderr)
                continue
            print(f"::notice::role '{role}' changed -> {playbook_path} tags [{', '.join(tags)}]", file=sys.stderr)

        result[playbook_path] = ",".join(sorted(resolved))

    # A dependency counts as deployed only if one of its dependents is.
    unmatched_roles = {
        role for role in pulled_by
        if role not in all_matched_roles and not pulled_by[role] & all_matched_roles
    }
    for role in unmatched_roles:
        print(f"::warning::role '{role}' changed but is not referenced in any of {', '.join(playbook_paths)}, ignoring", file=sys.stderr)

    print(json.dumps(result))


if __name__ == "__main__":
    main()
