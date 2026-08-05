#!/usr/bin/env python3
"""Map changed files to the ansible-playbook --tags needed to redeploy the
affected role(s), for one or more playbooks.

Usage: resolve_docker_tags.py <playbook.yml> [<playbook.yml> ...] < changed-files.txt
Changed file paths are read one per line from stdin.
Prints a JSON object {playbook_path: "tag1,tag2"} to stdout, one entry per
playbook argument (value is "" when nothing changed for that playbook).
"""
import json
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
    playbook_paths = sys.argv[1:]
    changed_files = [line.strip() for line in sys.stdin if line.strip()]
    roles = changed_roles(changed_files)

    result = {}
    all_matched_roles = set()
    for playbook_path in playbook_paths:
        role_tags = load_role_tags(playbook_path)
        matched, resolved = resolve_tags(role_tags, roles)
        all_matched_roles |= matched.keys()

        for role, tags in matched.items():
            print(f"::notice::role '{role}' changed -> {playbook_path} tags [{', '.join(tags)}]", file=sys.stderr)

        result[playbook_path] = ",".join(sorted(resolved))

    unmatched_roles = roles - all_matched_roles
    for role in unmatched_roles:
        print(f"::warning::role '{role}' changed but is not referenced in any of {', '.join(playbook_paths)}, ignoring", file=sys.stderr)

    print(json.dumps(result))


if __name__ == "__main__":
    main()
