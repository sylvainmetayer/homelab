"""Tests of check_restore_coverage.py: every borg backup is restore-tested or
excluded with a reason (Lint workflow: python -I -m unittest discover -s
.github/scripts -p 'test_*.py')."""

import json
import tempfile
import unittest
from pathlib import Path

import check_restore_coverage as coverage

TASKS = """---
- name: Something else
  ansible.builtin.debug:
    msg: x
- name: A block
  block:
    - name: Back up
      when: foo_backup_enabled
      ansible.builtin.include_role:
        name: borgmatic
        tasks_from: app.yml
      vars:
        borgmatic_app_name: {name}
"""
OTHER_ROLE = "- ansible.builtin.include_role:\n    name: other\n    tasks_from: app.yml\n  vars:\n    borgmatic_app_name: x\n"


def entry(repo, role="foo"):
    return {"host": "docker", "repo": repo, "role": role, "databases": []}


class CheckTest(unittest.TestCase):
    def test_tested_or_excluded_or_off_is_clean(self):
        backups = {"a": ("foo", True), "b": ("bar", True), "c": ("baz", False)}
        self.assertEqual(coverage.check(backups, {"a": entry("a")}, {"b": "raison"}), [])

    def test_app_key_may_differ_from_the_repository(self):
        backups = {"monica_v4": ("foo", True)}
        self.assertEqual(coverage.check(backups, {"monica": entry("monica_v4")}, {}), [])

    def test_backup_neither_tested_nor_excluded_fails(self):
        errors = coverage.check({"a": ("foo", True)}, {}, {})
        self.assertEqual(len(errors), 1)
        self.assertIn("sans test de restauration", errors[0])

    def test_entry_nobody_backs_up_fails(self):
        errors = coverage.check({}, {"a": entry("a")}, {})
        self.assertEqual(len(errors), 1)
        self.assertIn("aucun rôle", errors[0])

    def test_entry_of_another_role_fails(self):
        errors = coverage.check({"a": ("bar", True)}, {"a": entry("a")}, {})
        self.assertEqual(len(errors), 1)
        self.assertIn("rôle bar", errors[0])

    def test_entry_of_a_backup_turned_off_fails(self):
        errors = coverage.check({"a": ("foo", False)}, {"a": entry("a")}, {})
        self.assertEqual(len(errors), 1)
        self.assertIn("désactivée", errors[0])

    def test_tested_and_excluded_fails(self):
        errors = coverage.check({"a": ("foo", True)}, {"a": entry("a")}, {"a": "raison"})
        self.assertEqual(len(errors), 1)
        self.assertIn("le retirer", errors[0])

    def test_exclusion_without_a_reason_fails(self):
        errors = coverage.check({"a": ("foo", True)}, {}, {"a": "  "})
        self.assertEqual(len(errors), 1)
        self.assertIn("sans raison", errors[0])

    def test_exclusion_of_nothing_or_of_a_backup_off_fails(self):
        for backups in ({}, {"a": ("foo", False)}):
            with self.subTest(backups=backups):
                errors = coverage.check(backups, {}, {"a": "raison"})
                self.assertEqual(len(errors), 1)
                self.assertIn("aucune sauvegarde active", errors[0])


class FindBackupsTest(unittest.TestCase):
    def tree(self, tmp, tasks=TASKS.format(name="foo"), defaults="foo_backup_enabled: true\n",
             playbook="- hosts: all\n  roles:\n    - role: foo\n", host_vars=None):
        root = Path(tmp)
        for relative, text in {
            "ansible/roles/foo/tasks/main.yml": tasks,
            "ansible/roles/foo/defaults/main.yml": defaults,
            "ansible/host.yml": playbook,
            "ansible/host_vars/nas/variables.yaml": host_vars,
        }.items():
            if text is not None:
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
        return coverage.find_backups(root)

    def test_task_nested_in_a_block_is_found(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(self.tree(tmp), ({"foo": ("foo", True)}, []))

    def test_task_with_no_switch_is_on(self):
        tasks = TASKS.format(name="foo").replace("      when: foo_backup_enabled\n", "")
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(self.tree(tmp, tasks=tasks, defaults=None), ({"foo": ("foo", True)}, []))

    def test_include_of_another_role_is_no_backup(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(self.tree(tmp, tasks=OTHER_ROLE), ({}, []))

    def test_switch_false_in_the_defaults_is_off(self):
        with tempfile.TemporaryDirectory() as tmp:
            found, _ = self.tree(tmp, defaults="foo_backup_enabled: false\n")
            self.assertEqual(found, {"foo": ("foo", False)})

    def test_host_vars_setting_the_switch_turn_it_on(self):
        with tempfile.TemporaryDirectory() as tmp:
            found, _ = self.tree(tmp, defaults="foo_backup_enabled: false\n",
                                 host_vars="foo_backup_enabled: true\n")
            self.assertEqual(found, {"foo": ("foo", True)})

    def test_host_vars_setting_the_switch_off_turn_it_off(self):
        with tempfile.TemporaryDirectory() as tmp:
            found, _ = self.tree(tmp, host_vars="foo_backup_enabled: false\n")
            self.assertEqual(found, {"foo": ("foo", False)})

    def test_role_entry_turning_it_on_wins_over_the_defaults(self):
        playbook = ("- hosts: all\n  roles:\n    - role: foo\n      vars:\n"
                    "        foo_backup_enabled: '{{ x }}'\n")
        with tempfile.TemporaryDirectory() as tmp:
            found, _ = self.tree(tmp, defaults="foo_backup_enabled: false\n", playbook=playbook)
            self.assertEqual(found, {"foo": ("foo", True)})

    def test_one_variable_name_gives_one_backup_per_entry(self):
        playbook = """- hosts: all
  roles:
    - role: foo
    - role: foo
      vars:
        foo_service: demo
    - role: foo
      vars:
        foo_service: bench
        foo_backup_enabled: false
"""
        with tempfile.TemporaryDirectory() as tmp:
            found, errors = self.tree(
                tmp, tasks=TASKS.format(name='"{{ foo_service }}"'),
                defaults="foo_service: prod\nfoo_backup_enabled: true\n", playbook=playbook,
            )
        self.assertEqual(errors, [])
        self.assertEqual(found, {"prod": ("foo", True), "demo": ("foo", True), "bench": ("foo", False)})

    def test_name_that_does_not_resolve_fails(self):
        for name in ('"{{ foo_service }}"', '"{{ foo_service }}-x"'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as tmp:
                _, errors = self.tree(tmp, tasks=TASKS.format(name=name))
                self.assertEqual(len(errors), 1)

    def test_missing_name_fails(self):
        tasks = TASKS.format(name="foo").replace("      vars:\n        borgmatic_app_name: foo\n", "")
        with tempfile.TemporaryDirectory() as tmp:
            _, errors = self.tree(tmp, tasks=tasks)
        self.assertEqual(len(errors), 1)
        self.assertIn("borgmatic_app_name", errors[0])

    def test_one_repository_in_two_roles_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.tree(tmp)
            other = Path(tmp) / "ansible/roles/bar/tasks/main.yml"
            other.parent.mkdir(parents=True)
            other.write_text(TASKS.format(name="foo"), encoding="utf-8")
            _, errors = coverage.find_backups(Path(tmp))
        self.assertEqual(len(errors), 1)
        self.assertIn("deux rôles", errors[0])


class RepositoryTest(unittest.TestCase):
    """The repository itself: what the Lint step runs, and today's verdicts."""

    def setUp(self):
        self.backups, self.errors = coverage.find_backups(coverage.ROOT)

    def test_clean(self):
        manifest = json.loads((coverage.ROOT / ".github/restore-test/apps.json").read_text(encoding="utf-8"))
        self.assertEqual(self.errors, [])
        self.assertEqual(coverage.check(self.backups, manifest, coverage.EXCLUDED), [])

    def test_backups_turned_off_are_read_as_off(self):
        for name in ("kdrive", "demo_planning_kc", "exemple_planning"):
            with self.subTest(name=name):
                self.assertFalse(self.backups[name][1])

    def test_mediamanager_and_the_flip_instances_are_read_as_on(self):
        for name in ("mediamanager", "flip_planning", "demo_planning"):
            with self.subTest(name=name):
                self.assertTrue(self.backups[name][1])


if __name__ == "__main__":
    unittest.main()
