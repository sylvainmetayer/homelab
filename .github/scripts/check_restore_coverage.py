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
Its name is `borgmatic_app_name`, the repository's folder: apps.json's "repo". A
name that is one variable (flip_planning's instances) gives one backup per entry
of that role in a playbook.

It counts as off only when its `<x>_backup_enabled` switch is a literal false,
read from the playbook entry, else host_vars and group_vars, else the role
defaults. Anything else (a Jinja value too, which is not resolved) counts as on,
so turning kdrive_sync's backup on fails here until it is tested or excluded.

Usage (from the repository root, workflow Lint): check_restore_coverage.py
"""

import json
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
SWITCH = re.compile(r"\b\w+_backup_enabled\b")
ONE_VARIABLE = re.compile(r"^\{\{\s*(\w+)\s*\}\}$")

# Repository (borgmatic_app_name) -> why its restore is not tested.
EXCLUDED = {
    "mediamanager": (
        "à l'essai : ni moniteur Backup ni test de restauration tant que l'essai dure, "
        "et sa base PostgreSQL n'est pas sauvegardée (ansible/roles/mediamanager/README.md)"
    ),
}


def load_yaml(path):
    return yaml.safe_load(path.read_text(encoding="utf-8"))


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
    """Variables of host_vars and group_vars (keys only: SOPS files are not there)."""
    found = {}
    for pattern in ("ansible/host_vars/*/*.y*ml", "ansible/group_vars/*/*.y*ml"):
        for path in sorted(root.glob(pattern)):
            found.update(load_yaml(path) or {})
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


def role_backups(role, tasks, defaults, entries, outside):
    """([(repository, role, on)], errors) of one role's task list."""
    backups, errors = [], []
    for task in backup_tasks(tasks):
        task_vars = task.get("vars") or {}
        name = task_vars.get("borgmatic_app_name")
        if not isinstance(name, str) or not name:
            errors.append(f"{role} : sauvegarde sans borgmatic_app_name lisible dans ses vars:.")
            continue
        switches = SWITCH.findall(str(task.get("when", "")))

        def on(entry_vars):
            layers = {**defaults, **outside, **entry_vars}
            return not any(layers.get(switch) is False for switch in switches)

        variable = ONE_VARIABLE.match(name)
        if not variable and "{{" in name:
            errors.append(f"{role} : {name} ne se résout pas en un nom de dépôt.")
            continue
        if not variable:
            backups.append((name, role, any(on(e) for e in entries or [{}])))
            continue
        for entry_vars in entries or [{}]:
            instance = entry_vars.get(variable[1], defaults.get(variable[1]))
            if not isinstance(instance, str) or "{{" in instance:
                errors.append(f"{role} : {name} ne se résout pas en un nom de dépôt.")
                continue
            backups.append((instance, role, on(entry_vars)))
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
        for path in sorted((role_dir / "tasks").glob("*.y*ml")):
            backups, role_errors = role_backups(
                role, load_yaml(path), defaults, entries.get(role, []), outside
            )
            errors.extend(role_errors)
            for name, owner, on in backups:
                if name in found and found[name][0] != owner:
                    errors.append(f"{name} : dépôt de deux rôles ({found[name][0]}, {owner}).")
                found[name] = (owner, on or found.get(name, (owner, False))[1])
    return found, errors


def check(backups, manifest, excluded):
    """Errors: backups is {repository: (role, on)}, manifest is apps.json."""
    errors = []
    tested = {entry["repo"]: (app, entry["role"]) for app, entry in manifest.items()}
    for name, (role, on) in sorted(backups.items()):
        if on and name not in tested and name not in excluded:
            errors.append(
                f"{name} (rôle {role}) : sauvegardé, sans test de restauration. L'ajouter à "
                ".github/restore-test/apps.json, ou l'exclure avec sa raison dans EXCLUDED."
            )
    for repo, (app, role) in sorted(tested.items()):
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
