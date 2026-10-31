#!/usr/bin/env python3
"""Map changed files to the ansible-playbook --tags needed to redeploy the
affected role(s), for one or more playbooks.

Usage: resolve_docker_tags.py [--base SHA] <playbook.yml> [<playbook.yml> ...] < changed-files.txt
Changed file paths are read one per line from stdin.
Prints a JSON object {playbook_path: "tag1,tag2"} to stdout, one entry per
playbook argument (value is "" when nothing changed for that playbook, "all"
for the whole playbook).

Besides the roles, a change to a playbook itself deploys the tags of the
`roles:` entries it touched (their `vars:`, their tags...), compared as YAML
with the playbook at --base (comments and layout deploy nothing); any other
change to it (pre_tasks, tasks, play keys), or no readable --base, deploys the
whole playbook. A change under host_vars/<host>/, <host> being the play's
`hosts:`, deploys the whole playbook too: which role reads which variable is
not known here. A change to a file every playbook reads (SHARED_PATHS:
group_vars/all, the shared tasks/, requirements.yml) deploys every playbook
given, whole.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

import yaml

GENERIC_TAGS = {"app", "setup"}
ROLE_PATH_RE = re.compile(r"^ansible/roles/([^/]+)/")
# A role's README.md is documentation for humans and agents, never read by
# Ansible: changing it redeploys nothing.
ROLE_README_RE = re.compile(r"^ansible/roles/[^/]+/README\.md$")
# Seuls les playbooks à la racine de ansible/ peuvent être lus : le fichier
# ouvert vient de cette liste, jamais de l'argument (pas de traversée de chemin).
ANSIBLE_DIR = Path(__file__).resolve().parents[2] / "ansible"
PLAYBOOKS = {p.name: p for p in ANSIBLE_DIR.glob("*.y*ml")}
# Playbooks never run by the deploy workflow (no key of the NAS nor of the
# Proxmox host in the GitHub secrets).
MANUAL_PLAYBOOKS = ["nas.yml", "pve.yml"]
# ansible-playbook --tags all: every task except those tagged never.
WHOLE_PLAYBOOK = "all"
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
# Read by every playbook, hence by every role: a change runs each playbook
# given whole. group_vars/all: variables of every host; tasks/: pre_tasks
# imported by the playbooks (pangolin_config_outputs.yml); requirements.yml:
# the versions of the galaxy roles and collections (geerlingguy.docker,
# devsec.hardening...) the roles run. Left out, deliberately: secrets.sops.yaml
# (a rotation is applied by hand, in order, docs/runbooks/rotation-des-secrets.md),
# and what changes no host (ansible.cfg, known_hosts, inventory/: the CI writes
# its own, mise.toml, molecule/).
SHARED_PATH_RE = re.compile(r"^ansible/(?:(?:group_vars/all|tasks)/.+|requirements\.yml)$")


def safe_playbook_path(playbook_path):
    path = Path(playbook_path).resolve()
    known = PLAYBOOKS.get(path.name)
    if known is None or known.resolve() != path:
        sys.exit(f"::error::{playbook_path} is not a playbook of {ANSIBLE_DIR}, refusing to read it")
    return known


def entry_tags(entry):
    # `tags` is either "a,b" or a YAML list ([decommission, never]).
    tags = entry.get("tags", "")
    if isinstance(tags, str):
        tags = tags.split(",")
    return [t for t in (str(t).strip() for t in tags) if t]


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
        known = role_tags.setdefault(role_name, [])
        known.extend(t for t in entry_tags(entry) if t not in known)
    return role_tags


def changed_entry_tags(old, new):
    """Tags to deploy for a playbook going from `old` to `new` (parsed YAML).

    Only the `roles:` entries may differ: each entry of `new` with no equal
    entry in `old` (added or changed; a removed one deploys nothing) brings its
    specific tags, its generic ones when it has no other (geerlingguy.docker:
    setup), nothing when tagged never. A specific tag that other entries of the
    play also carry (monitoring) is dropped when the entry has one of its own
    (beszel_agent): it would deploy those entries too. Returns None (whole
    playbook) when anything else differs, or for a changed entry with no tag
    (it runs under `all` only)."""
    if not isinstance(old, list) or not isinstance(new, list) or len(old) != len(new):
        return None
    tags = set()
    for old_play, new_play in zip(old, new):
        if not isinstance(old_play, dict) or not isinstance(new_play, dict):
            return None
        if {k: v for k, v in old_play.items() if k != "roles"} != {k: v for k, v in new_play.items() if k != "roles"}:
            return None
        new_entries = new_play.get("roles") or []
        tag_count = {}
        for entry in new_entries:
            for tag in set(entry_tags(entry) if isinstance(entry, dict) else []):
                tag_count[tag] = tag_count.get(tag, 0) + 1
        # Matched as a multiset: a second copy of an entry is an added one.
        unmatched_old = list(old_play.get("roles") or [])
        for entry in new_entries:
            if entry in unmatched_old:
                unmatched_old.remove(entry)
                continue
            entry_tag_list = entry_tags(entry) if isinstance(entry, dict) else []
            if not entry_tag_list:
                return None
            if "never" in entry_tag_list:
                continue
            specific = set(entry_tag_list) - GENERIC_TAGS
            own = {t for t in specific if tag_count[t] == 1}
            tags |= own or specific or set(entry_tag_list)
    return tags


def playbook_at(base, playbook):
    """The playbook's parsed YAML at commit `base`, or None if unreadable."""
    if not base or not SHA_RE.match(base):
        return None
    out = subprocess.run(
        ["git", "show", f"{base}:ansible/{playbook.name}"],
        cwd=ANSIBLE_DIR.parent, capture_output=True, text=True, check=False,
    )
    if out.returncode != 0:
        return None
    try:
        return yaml.safe_load(out.stdout)
    except yaml.YAMLError:
        return None


def playbook_change_tags(playbook_path, changed_files, base):
    """Tags a change to the playbook itself or to its host's host_vars deploys:
    a set, {WHOLE_PLAYBOOK} for the whole playbook, empty when neither changed."""
    playbook = safe_playbook_path(playbook_path)
    # Most merges touch only roles: no need to parse the playbook again.
    if f"ansible/{playbook.name}" not in changed_files and not any(
            p.startswith("ansible/host_vars/") for p in changed_files):
        return set()
    with open(playbook) as f:
        new = yaml.safe_load(f)
    # `hosts:` is a pattern string ("flip") or a list of them.
    hosts = set()
    for play in new:
        play_hosts = play.get("hosts", []) if isinstance(play, dict) else []
        hosts.update([play_hosts] if isinstance(play_hosts, str) else play_hosts)
    for path in changed_files:
        parts = path.split("/")
        if len(parts) > 3 and parts[:2] == ["ansible", "host_vars"] and parts[2] in hosts:
            print(f"::notice::{path} changed -> whole {playbook_path}", file=sys.stderr)
            return {WHOLE_PLAYBOOK}
    if f"ansible/{playbook.name}" not in changed_files:
        return set()
    old = playbook_at(base, playbook)
    tags = None if old is None else changed_entry_tags(old, new)
    if tags is None:
        reason = "no readable base to compare with" if old is None else "not only role entries changed"
        print(f"::notice::{playbook_path} changed ({reason}) -> whole playbook", file=sys.stderr)
        return {WHOLE_PLAYBOOK}
    if tags:
        print(f"::notice::{playbook_path} role entries changed -> tags [{', '.join(sorted(tags))}]", file=sys.stderr)
    else:
        print(f"::notice::{playbook_path} changed, no role entry to deploy (comments, layout, removed entry)", file=sys.stderr)
    return tags


def shared_changes(changed_files):
    """Changed files every playbook reads (SHARED_PATH_RE), sorted."""
    return sorted(p for p in changed_files if SHARED_PATH_RE.match(p))


def shared_change_tags(changed_files):
    """{WHOLE_PLAYBOOK} for every playbook when a shared file changed, else empty."""
    shared = shared_changes(changed_files)
    if not shared:
        return set()
    print(f"::notice::{', '.join(shared)} changed -> every playbook whole", file=sys.stderr)
    return {WHOLE_PLAYBOOK}


def changed_roles(changed_files):
    roles = set()
    for path in changed_files:
        if ROLE_README_RE.match(path):
            continue
        match = ROLE_PATH_RE.match(path)
        if match:
            roles.add(match.group(1))
    return roles


def role_metas(roles_dir):
    """Each role's meta file as Ansible picks it: the first of main.yml,
    main.yaml, main.json that exists (it reads only one, never merges them)."""
    for role_dir in sorted(roles_dir.iterdir()):
        for ext in ("yml", "yaml", "json"):
            meta = role_dir / "meta" / f"main.{ext}"
            if meta.is_file():
                yield meta
                break


def add_dependents(roles, roles_dir=ANSIBLE_DIR / "roles"):
    """A role pulled in only through meta/main.y(a)ml `dependencies` (nas_storage)
    has no entry, hence no tag, in any playbook: redeploy the roles that
    depend on it instead, since they run it under their own tags.

    Returns the expanded role set and, for each changed role, the roles that
    depend on it (transitively)."""
    dependents = {}
    for meta in role_metas(roles_dir):
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


def unreferenced_roles(pulled_by, referenced, deployed):
    """Changed roles that no playbook runs, to warn about.

    `referenced`: roles having an entry in a playbook, `never` included (a
    change to decommission_app gets its own notice, not this warning).
    `deployed`: roles having an entry NOT tagged `never`. A dependency counts
    as deployed only through a deployed dependent: one whose sole dependent is
    tagged `never` is never run by a merge, and must be reported."""
    return {
        role for role, dependents in pulled_by.items()
        if role not in referenced and not dependents & deployed
    }


def manual_playbooks_by_role():
    """role -> the manual playbooks that apply it (jellyfin: nas.yml only)."""
    by_role = {}
    for playbook in MANUAL_PLAYBOOKS:
        for role in load_role_tags(ANSIBLE_DIR / playbook):
            by_role.setdefault(role, []).append(playbook)
    return by_role


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="", help="commit to compare changed playbooks with")
    parser.add_argument("playbooks", nargs="+")
    args = parser.parse_args()
    playbook_paths = args.playbooks
    changed_files = [line.strip() for line in sys.stdin if line.strip()]
    roles, pulled_by = add_dependents(changed_roles(changed_files))
    shared = shared_change_tags(changed_files)

    result = {}
    referenced = set()
    deployed = set()
    for playbook_path in playbook_paths:
        role_tags = load_role_tags(playbook_path)
        matched, resolved = resolve_tags(role_tags, roles)
        referenced |= matched.keys()

        for role, tags in matched.items():
            # A dependent is matched because a role it depends on changed.
            what = "changed" if role in pulled_by else "depends on a changed role"
            if "never" in tags:
                print(f"::notice::role '{role}' {what} but is tagged never in {playbook_path}, not deployed", file=sys.stderr)
                continue
            deployed.add(role)
            print(f"::notice::role '{role}' {what} -> {playbook_path} tags [{', '.join(tags)}]", file=sys.stderr)

        resolved = set(resolved) | shared | playbook_change_tags(playbook_path, changed_files, args.base)
        if WHOLE_PLAYBOOK in resolved:
            resolved = {WHOLE_PLAYBOOK}
        result[playbook_path] = ",".join(sorted(resolved))

    unreferenced = sorted(unreferenced_roles(pulled_by, referenced, deployed))
    # Roles of a playbook run by hand only (nas.yml, pve.yml: no key of those
    # hosts in the GitHub secrets) are expected here: a notice, not a warning. Read only when
    # needed: most merges leave no unreferenced role.
    manual_roles = manual_playbooks_by_role() if unreferenced else {}
    for role in unreferenced:
        if role in manual_roles:
            print(f"::notice::role '{role}' changed, deployed by hand only ({', '.join(manual_roles[role])}), not by CI", file=sys.stderr)
            continue
        print(f"::warning::role '{role}' changed but is not deployed by any of {', '.join(playbook_paths)} (no entry, or only through roles tagged never), ignoring", file=sys.stderr)

    print(json.dumps(result))


if __name__ == "__main__":
    main()
