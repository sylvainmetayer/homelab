"""Tests of check_container_hardening.py: no-new-privileges on every compose
service outside the listed exceptions (Lint workflow: python -I -m unittest
discover -s .github/scripts -p 'test_*.py')."""

import tempfile
import unittest
from pathlib import Path

import check_container_hardening as hardening

TEMPLATE = """---
services:
  app:
    image: example/app:1@sha256:abc
    security_opt:
      - no-new-privileges:true
  # no-new-privileges:true dans un commentaire ne compte pas
  worker:
    # - no-new-privileges:true
    image: "{{ worker_image }}"
{% if keycloak_enabled %}
  keycloak:
    image: example/kc:1
    security_opt: ["no-new-privileges:true"]
{% endif %}
  disabled:
    security_opt:
      - no-new-privileges:false

networks:
  app:
    internal: true
  {{ prefix }}:
    external: true
volumes:
  data:
"""


class ServicesTest(unittest.TestCase):
    def test_reads_each_service_through_jinja(self):
        self.assertEqual(
            hardening.services(TEMPLATE),
            [("app", True), ("worker", False), ("keycloak", True), ("disabled", False)],
        )

    def test_a_key_outside_services_is_no_service(self):
        found = hardening.services("networks:\n  app:\n    internal: true\n")
        self.assertEqual(found, [])

    def test_jinja_in_column_0_does_not_close_services(self):
        for line in ("{# note #}", "{{ extra }}", "{% if a"):
            text = f"services:\n  a:\n    image: x\n{line}\n  b:\n    image: y\n"
            self.assertEqual(
                [name for name, _ in hardening.services(text)], ["a", "b"], line
            )

    def test_comment_after_services_key(self):
        text = "services: # les apps\n  a:\n    image: x\n"
        self.assertEqual(hardening.services(text), [("a", False)])

    def test_option_outside_security_opt_does_not_count(self):
        for line in (
            "image: x # hors cap_drop, no-new-privileges:true plus tard",
            'command: ["no-new-privileges:true"]',
            "command:\n      - no-new-privileges:true",
        ):
            text = f"services:\n  a:\n    {line}\n"
            self.assertEqual(hardening.services(text), [("a", False)], line)

    def test_flow_form_after_another_option(self):
        text = 'services:\n  a:\n    security_opt: ["x:y", "no-new-privileges:true"]\n'
        self.assertEqual(hardening.services(text), [("a", True)])

    def test_key_with_anchor_or_jinja_starts_a_service(self):
        text = (
            "services:\n  a: &a\n    security_opt:\n      - no-new-privileges:true\n"
            "  {{ prefix }}-b:\n    image: x\n"
        )
        self.assertEqual(
            hardening.services(text), [("a", True), ("{{ prefix }}-b", False)]
        )


class CheckTest(unittest.TestCase):
    def test_clean(self):
        found = {("a", "x"): True, ("b", "y"): False}
        self.assertEqual(hardening.check(found, {"b": ("raison", ["y"])}), [])

    def test_unlisted_service_without_the_option_fails(self):
        errors = hardening.check({("a", "x"): False}, {})
        self.assertEqual(len(errors), 1)
        self.assertIn("a/x", errors[0])

    def test_listed_service_with_the_option_fails(self):
        errors = hardening.check({("a", "x"): True}, {"a": ("raison", ["x"])})
        self.assertEqual(len(errors), 1)
        self.assertIn("EXCEPTIONS", errors[0])

    def test_exception_without_a_reason_fails(self):
        errors = hardening.check({("a", "x"): False}, {"a": (" ", ["x"])})
        self.assertEqual(len(errors), 1)
        self.assertIn("sans raison", errors[0])

    def test_listed_service_that_is_gone_fails(self):
        errors = hardening.check({}, {"a": ("raison", ["x"])})
        self.assertEqual(len(errors), 1)
        self.assertIn("absent", errors[0])


class TreeTest(unittest.TestCase):
    def test_scan_a_service_read_twice_must_have_the_option_each_time(self):
        hardened = "  x:\n    security_opt:\n      - no-new-privileges:true\n"
        branches = f"services:\n{{% if a %}}\n{hardened}{{% else %}}\n  x:\n    image: a\n"
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            role = root / "ansible/roles/foo/templates/compose.yaml"
            other = root / "compose/foo/compose.yaml"
            for path in (role, other):
                path.parent.mkdir(parents=True)
            role.write_text(branches, encoding="utf-8")
            other.write_text(f"services:\n{hardened}", encoding="utf-8")
            self.assertEqual(hardening.scan(root), ({("foo", "x"): False}, []))

    def test_scan_reports_a_file_with_no_service(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "compose/foo/compose.yaml"
            path.parent.mkdir(parents=True)
            path.write_text('"services":\n  x:\n    image: a\n', encoding="utf-8")
            self.assertEqual(
                hardening.scan(root), ({}, [Path("compose/foo/compose.yaml")])
            )

    def test_owner_of_role_and_compose_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            role = root / "ansible/roles/foo/templates/compose.yaml"
            other = root / "compose/bar/compose.yaml"
            for path in (role, other):
                path.parent.mkdir(parents=True)
                path.write_text("services:\n  x:\n    image: a\n", encoding="utf-8")
            self.assertEqual(list(hardening.compose_files(root)), [role, other])
            self.assertEqual(hardening.owner(root, role), "foo")
            self.assertEqual(hardening.owner(root, other), "bar")


if __name__ == "__main__":
    unittest.main()
