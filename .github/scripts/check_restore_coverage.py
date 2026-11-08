#!/usr/bin/env python3
"""Every borg backup is restore-tested, or excluded with a written reason.

.github/restore-test/README.md: pangolin_config's `tofu test` keeps apps.json
equal to the backup monitors, so a backup with no monitor (the shared borgmatic
template does not require one) is tested nowhere and nothing says so. This check
(Lint workflow) reads what the roles back up and fails on a backup neither in
apps.json nor in EXCLUDED, on an apps.json entry no role backs up (or another
role than it names), and on an exclusion that is stale or has no reason: the
list only says what is true.

A backup is a task of a role including `borgmatic` with `tasks_from: app.yml`.
Its name is `borgmatic_app_name`, the repository's folder: apps.json's "repo". It
exists once per entry of that role in a playbook (none for a role no playbook
runs), and a name that is one variable (flip_planning's instances) gives one
backup per entry.

It counts as off only when a `<x>_backup_enabled` switch its `when:` requires is
a literal false, or one variable that is one, read from the playbook entry, else
host_vars and group_vars, else the role defaults. Anything else (other Jinja, a
`not` or an `or`, which guarantee nothing) counts as on, so turning kdrive_sync's
backup on fails here until it is tested or excluded.

Usage (from the repository root, workflow Lint): check_restore_coverage.py
"""

import json
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
SWITCH = re.compile(r"(\w+_backup_enabled)(?:\s*\|\s*bool)?")
ONE_VARIABLE = re.compile(r"^\{\{\s*(\w+)\s*\}\}$")

# Repository (borgmatic_app_name) -> why its restore is not tested.
EXCLUDED = {
    "mediamanager": (
        "à l'essai : ni moniteur Backup ni test de restauration tant que l'essai dure "
        "(ansible/roles/mediamanager/README.md)"
    ),
}


class Loader(yaml.SafeLoader):
    """SafeLoader that tolerates Ansible's custom tags (!vault, !unsafe)."""


Loader.add_multi_constructor("!", lambda loader, suffix, node: None)


def load_yaml(path):
    return yaml.load(path.read_text(encoding="utf-8"), Loader=Loader)  # noqa: S506 - SafeLoader subclass


def walk_tasks(tasks):
    """Every task of a task file, those of block/rescue/always included."""
    for task in tasks if isinstance(tasks, list) else []:
        yield task
        for key in ("block", "rescue", "always"):
            yield from walk_tasks(task.get(key))


def backup_tasks(tasks):
    """The tasks of a task file that call the shared borgmatic template."""
    for task in walk_tasks(tasks):
        for module in ("include_role", "import_role"):
            call = task.get(f"ansible.builtin.{module}") or task.get(module)
            if (
                isinstance(call, dict)
                and call.get("name") == "borgmatic"
                and str(call.get("tasks_from", "")).removesuffix(".yml") == "app"
            ):
                yield task


def variables_set_outside_roles(root):
    """Variables of host_vars and group_vars (SOPS files are not there).

    Which host runs which role is not read, so hosts are not told apart: the first
    value other than false wins, host_vars before group_vars. A false on one host
    must not hide the backup of another, and false needs every file to agree.
    """
    found = {}
    for pattern in ("ansible/host_vars/*/*.y*ml", "ansible/group_vars/*/*.y*ml"):
        for path in sorted(root.glob(pattern)):
            for key, value in (load_yaml(path) or {}).items():
                if found.get(key, False) is False:
                    found[key] = value
    return found


def playbook_entries(root):
    """{role: [vars of each of its entries in a playbook]}."""
    entries = {}
    for path in [*sorted(root.glob("ansible/*.yml")), *sorted(root.glob("ansible/*.yaml"))]:
        plays = load_yaml(path)
        for play in plays if isinstance(plays, list) else []:
            for entry in play.get("roles") or []:
                if isinstance(entry, dict) and "role" in entry:
                    entries.setdefault(entry["role"], []).append(entry.get("vars") or {})
    return entries


def required_switches(when):
    """The switches a `when:` requires: any of them false skips the task. A
    condition with an `or` requires nothing, a `not x` does not require x."""
    switches = []
    for condition in when if isinstance(when, list) else [when]:
        if not re.search(r"\bor\b", str(condition)):
            terms = re.split(r"\s+and\s+", str(condition).strip())
            switches += [match[1] for match in map(SWITCH.fullmatch, terms) if match]
    return switches


def switch_is_off(switch, layers):
    value = layers.get(switch)
    variable = ONE_VARIABLE.match(value) if isinstance(value, str) else None
    return (layers.get(variable[1]) if variable else value) is False


def role_backups(role, tasks, defaults, entries, outside):
    """([(repository, on)], errors) of one role's task list."""
    backups, errors = [], []
    for task in backup_tasks(tasks):
        name = (task.get("vars") or {}).get("borgmatic_app_name")
        if not isinstance(name, str) or not name:
            errors.append(f"{role} : sauvegarde sans borgmatic_app_name lisible dans ses vars:.")
            continue
        variable = ONE_VARIABLE.match(name)
        if not variable and "{{" in name:
            errors.append(f"{role} : {name} ne se résout pas en un nom de dépôt.")
            continue
        switches = required_switches(task.get("when"))
        for entry_vars in entries:
            layers = {**defaults, **outside, **entry_vars}
            repository = layers.get(variable[1]) if variable else name
            if not isinstance(repository, str) or "{{" in repository:
                errors.append(f"{role} : {name} ne se résout pas en un nom de dépôt.")
                continue
            backups.append((repository, not any(switch_is_off(s, layers) for s in switches)))
    return backups, errors


def find_backups(root):
    """({repository: (role, on)}, errors) over every role but borgmatic itself."""
    entries = playbook_entries(root)
    outside = variables_set_outside_roles(root)
    found, errors = {}, []
    for role_dir in sorted(root.glob("ansible/roles/*")):
        role = role_dir.name
        if role == "borgmatic":
            continue
        defaults_path = role_dir / "defaults" / "main.yml"
        defaults = (load_yaml(defaults_path) or {}) if defaults_path.exists() else {}
        for path in sorted((role_dir / "tasks").rglob("*.y*ml")):
            backups, role_errors = role_backups(
                role, load_yaml(path), defaults, entries.get(role, []), outside
            )
            errors.extend(role_errors)
            for name, on in backups:
                if name in found and found[name][0] != role:
                    errors.append(f"{name} : dépôt de deux rôles ({found[name][0]}, {role}).")
                found[name] = (role, on or found.get(name, (role, False))[1])
    return found, errors


def check(backups, manifest, excluded):
    """Errors: backups is {repository: (role, on)}, manifest is apps.json."""
    errors = []
    tested = {entry["repo"] for entry in manifest.values()}
    for name, (role, on) in sorted(backups.items()):
        if on and name not in tested and name not in excluded:
            errors.append(
                f"{name} (rôle {role}) : sauvegardé, sans test de restauration. L'ajouter à "
                ".github/restore-test/apps.json, ou l'exclure avec sa raison dans EXCLUDED."
            )
    for app, entry in sorted(manifest.items()):
        repo, role = entry["repo"], entry["role"]
        if repo not in backups:
            errors.append(f"apps.json, {app} : aucun rôle ne sauvegarde le dépôt {repo}.")
        elif backups[repo][0] != role:
            errors.append(f"apps.json, {app} : le dépôt {repo} est celui du rôle {backups[repo][0]}, pas {role}.")
        elif not backups[repo][1]:
            errors.append(f"apps.json, {app} : la sauvegarde du dépôt {repo} est désactivée.")
        if repo in excluded:
            errors.append(f"{repo} : dans apps.json et dans EXCLUDED, le retirer d'EXCLUDED.")
    for name, reason in sorted(excluded.items()):
        if not reason.strip():
            errors.append(f"{name} : exclusion sans raison dans EXCLUDED.")
        if not backups.get(name, ("", False))[1]:
            errors.append(f"{name} : dans EXCLUDED, mais aucune sauvegarde active : l'en retirer.")
    return errors


def main():
    backups, errors = find_backups(ROOT)
    manifest = json.loads((ROOT / ".github/restore-test/apps.json").read_text(encoding="utf-8"))
    errors.extend(check(backups, manifest, EXCLUDED))
    for error in errors:
        print(error)
    if not errors:
        off = sorted(name for name, (_, on) in backups.items() if not on)
        print(
            f"{len(manifest)} dépôts testés, {len(EXCLUDED)} exclus "
            f"({', '.join(sorted(EXCLUDED))}), désactivés : {', '.join(off)}."
        )
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
