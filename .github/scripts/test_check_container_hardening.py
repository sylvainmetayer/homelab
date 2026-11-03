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
            {"app": True, "worker": False, "keycloak": True, "disabled": False},
        )

    def test_a_key_outside_services_is_no_service(self):
        found = hardening.services("networks:\n  app:\n    internal: true\n")
        self.assertEqual(found, {})


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

    def test_listed_service_that_is_gone_fails(self):
        errors = hardening.check({}, {"a": ("raison", ["x"])})
        self.assertEqual(len(errors), 1)
        self.assertIn("absent", errors[0])


class TreeTest(unittest.TestCase):
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
