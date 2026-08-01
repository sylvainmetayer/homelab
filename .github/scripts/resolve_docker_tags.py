#!/usr/bin/env python3
"""Map changed files to the ansible-playbook --tags needed to redeploy the
affected docker.yml role(s).

Usage: resolve_docker_tags.py <path-to-docker.yml> < changed-files.txt
Changed file paths are read one per line from stdin.
Prints the resolved comma-separated tag list to stdout (empty if nothing to do).
"""
import re
import sys

import yaml

GENERIC_TAGS = {"app", "setup"}
ROLE_PATH_RE = re.compile(r"^ansible/roles/([^/]+)/")


def load_role_tags(playbook_path):
    with open(playbook_path) as f:
        playbook = yaml.safe_load(f)

    role_tags = {}
    for entry in playbook[0]["roles"]:
        if isinstance(entry, str):
            continue
        role_name = entry.get("role", entry.get("name"))
        tags = str(entry.get("tags", ""))
        role_tags[role_name] = [t.strip() for t in tags.split(",") if t.strip()]
    return role_tags


def changed_roles(changed_files):
    roles = set()
    for path in changed_files:
        match = ROLE_PATH_RE.match(path)
        if match:
            roles.add(match.group(1))
    return roles


def resolve_tags(role_tags, roles):
    matched = {role: role_tags[role] for role in roles if role in role_tags}

    all_tags = {tag for tags in matched.values() for tag in tags}
    specific = all_tags - GENERIC_TAGS

    resolved = specific if specific else all_tags
    return matched, resolved


def main():
    (playbook_path,) = sys.argv[1:]
    changed_files = [line.strip() for line in sys.stdin if line.strip()]

    role_tags = load_role_tags(playbook_path)
    roles = changed_roles(changed_files)
    matched, resolved = resolve_tags(role_tags, roles)

    for role, tags in matched.items():
        print(f"::notice::role '{role}' changed -> tags [{', '.join(tags)}]", file=sys.stderr)

    unmatched_roles = roles - matched.keys()
    for role in unmatched_roles:
        print(f"::warning::role '{role}' changed but is not referenced in {playbook_path}, ignoring", file=sys.stderr)

    print(",".join(sorted(resolved)))


if __name__ == "__main__":
    main()
