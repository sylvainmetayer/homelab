"""Tests of check_secret_rotation.py: coverage of the SOPS files, entry
validation, due dates, push (Lint workflow: python -I -m unittest discover -s
.github/scripts -p 'test_*.py')."""

import datetime
import io
import os
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

import check_secret_rotation as rotation

TODAY = datetime.date(2026, 10, 28)

ROOT_SOPS = """\
HCLOUD_TOKEN: ENC[AES256_GCM,data:xx,iv:xx,tag:xx,type:str]
#ENC[AES256_GCM,data:comment,iv:xx,tag:xx,type:comment]
home_ip: ENC[AES256_GCM,data:xx,iv:xx,tag:xx,type:str]
sops:
    age:
        - recipient: age1xxx
    lastmodified: "2026-10-28T00:00:00Z"
"""
ANSIBLE_SOPS = """\
wiki_db_password: ENC[AES256_GCM,data:xx,iv:xx,tag:xx,type:str]
beszel_agent_tokens:
    docker: ENC[AES256_GCM,data:xx,iv:xx,tag:xx,type:str]
sops:
    mac: ENC[AES256_GCM,data:xx,iv:xx,tag:xx,type:str]
"""
RUNBOOK = """\
# Rotation

## Jetons de fournisseurs (chaque année)

### Hetzner

```bash
# pas un titre
```

### Secret d'appli lu par Ansible
"""
INVENTORY = """\
# commentaire
secrets:
  # --- secrets.sops.yaml ---
  - key: HCLOUD_TOKEN
    file: secrets.sops.yaml
    kind: provider
    last_rotated: 2026-01-09
    estimated: true
    how: docs/rb.md#hetzner
  - key: home_ip
    file: secrets.sops.yaml
    kind: identifier

  - key: wiki_db_password
    file: ansible/secrets.sops.yaml
    kind: database
    last_rotated: 2026-01-14
    estimated: true
    how: docs/rb.md
  - key: beszel_agent_tokens
    file: ansible/secrets.sops.yaml
    kind: application
    last_rotated: "2026-10-26"
    estimated: false
    how: docs/rb.md#secret-dappli-lu-par-ansible
"""
SECOURS_RUNBOOK = """\
---
# commentaire
dernier_test: 2026-10-20
---

# Tester la clé secours
"""


class Repo:
    """A temporary repository root with the two SOPS files and a runbook."""

    def __init__(self, inventory=INVENTORY, root_sops=ROOT_SOPS, ansible_sops=ANSIBLE_SOPS):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "ansible").mkdir()
        (self.root / "docs").mkdir()
        (self.root / "secrets.sops.yaml").write_text(root_sops, encoding="utf-8")
        (self.root / "ansible/secrets.sops.yaml").write_text(ansible_sops, encoding="utf-8")
        (self.root / "docs/rb.md").write_text(RUNBOOK, encoding="utf-8")
        (self.root / rotation.INVENTORY).write_text(inventory, encoding="utf-8")
        (self.root / rotation.SECOURS_TEST).parent.mkdir(parents=True)
        (self.root / rotation.SECOURS_TEST).write_text(SECOURS_RUNBOOK, encoding="utf-8")

    def errors(self, today=TODAY):
        entries, keys = rotation.load(self.root)
        return rotation.validate(entries, keys, today, self.root)

    def close(self):
        self.tmp.cleanup()


class SopsKeysTest(unittest.TestCase):
    def test_top_level_keys_only_without_sops_and_comments(self):
        self.assertEqual(rotation.sops_keys(ROOT_SOPS), {"HCLOUD_TOKEN", "home_ip"})
        self.assertEqual(rotation.sops_keys(ANSIBLE_SOPS), {"wiki_db_password", "beszel_agent_tokens"})

    def test_any_key_characters(self):
        text = 'a-b: ENC[x]\nc.d: ENC[x]\n"e f": ENC[x]\n---\nsops:\n    mac: ENC[x]\n'
        self.assertEqual(rotation.sops_keys(text), {"a-b", "c.d", "e f"})


class ParseTest(unittest.TestCase):
    def test_entries_and_scalars(self):
        entries = rotation.parse_inventory(INVENTORY)
        self.assertEqual([e["key"] for e in entries], ["HCLOUD_TOKEN", "home_ip", "wiki_db_password", "beszel_agent_tokens"])
        self.assertIs(entries[0]["estimated"], True)
        self.assertIs(entries[3]["estimated"], False)
        self.assertEqual(entries[3]["last_rotated"], "2026-10-26")
        self.assertEqual(entries[0]["line"], 4)

    def test_rejects_unknown_field(self):
        with self.assertRaisesRegex(rotation.InventoryError, "champ inconnu"):
            rotation.parse_inventory("secrets:\n  - key: a\n    owner: me\n")

    def test_rejects_bad_indentation(self):
        with self.assertRaisesRegex(rotation.InventoryError, "format inattendu"):
            rotation.parse_inventory("secrets:\n  - key: a\n      kind: provider\n")

    def test_rejects_duplicate_field(self):
        with self.assertRaisesRegex(rotation.InventoryError, "en double"):
            rotation.parse_inventory("secrets:\n  - key: a\n    key: b\n")

    def test_requires_root(self):
        with self.assertRaisesRegex(rotation.InventoryError, "secrets:"):
            rotation.parse_inventory("- key: a\n")


class SlugTest(unittest.TestCase):
    def test_github_anchors(self):
        self.assertEqual(rotation.slug(" Clés S3 des states"), "clés-s3-des-states")
        self.assertEqual(rotation.slug("Clés de chiffrement (sur incident)"), "clés-de-chiffrement-sur-incident")
        self.assertEqual(rotation.slug("Secrets du site sylvain.dev"), "secrets-du-site-sylvaindev")
        self.assertEqual(rotation.slug("Secret d'appli lu par Ansible"), "secret-dappli-lu-par-ansible")

    def test_fenced_lines_are_not_headings(self):
        self.assertNotIn("pas-un-titre", rotation.anchors(RUNBOOK))
        indented = "- liste\n\n  ```bash\n# pas un titre\n  ```\n"
        self.assertNotIn("pas-un-titre", rotation.anchors(indented))

    def test_duplicate_headings_get_a_suffix(self):
        self.assertEqual(rotation.anchors("## OVH\n### OVH\n#!/bin/sh\n"), {"ovh", "ovh-1"})


class ValidateTest(unittest.TestCase):
    def setUp(self):
        self.repo = None

    def tearDown(self):
        if self.repo:
            self.repo.close()

    def make(self, **kwargs):
        self.repo = Repo(**kwargs)
        return self.repo

    def test_valid_inventory(self):
        self.assertEqual(self.make().errors(), [])

    def test_key_missing_from_inventory(self):
        errors = self.make(root_sops=ROOT_SOPS.replace("sops:", "NEW_TOKEN: ENC[x]\nsops:")).errors()
        self.assertEqual(errors, ["secrets.sops.yaml : la clé NEW_TOKEN manque à secrets-rotation.yaml"])

    def test_entry_without_key(self):
        errors = self.make(root_sops=ROOT_SOPS.replace("HCLOUD_TOKEN", "OTHER")).errors()
        self.assertTrue(any("HCLOUD_TOKEN (secrets.sops.yaml) : la clé n'existe plus" in e for e in errors), errors)

    def test_same_key_in_the_other_file_does_not_count(self):
        inventory = INVENTORY.replace("  - key: home_ip\n    file: secrets.sops.yaml", "  - key: home_ip\n    file: ansible/secrets.sops.yaml")
        errors = self.make(inventory=inventory).errors()
        self.assertIn("secrets.sops.yaml : la clé home_ip manque à secrets-rotation.yaml", errors)

    def test_duplicate_entry(self):
        extra = "  - key: home_ip\n    file: secrets.sops.yaml\n    kind: identifier\n"
        errors = self.make(inventory=INVENTORY + extra).errors()
        self.assertTrue(any("entrée en double" in e for e in errors), errors)

    def test_unknown_kind_and_file(self):
        inventory = INVENTORY.replace("kind: database", "kind: yearly").replace(
            "  - key: home_ip\n    file: secrets.sops.yaml", "  - key: home_ip\n    file: other.sops.yaml"
        )
        errors = self.make(inventory=inventory).errors()
        self.assertTrue(any("nature 'yearly' inconnue" in e for e in errors), errors)
        self.assertTrue(any("fichier inconnu" in e for e in errors), errors)

    def test_dated_fields(self):
        inventory = INVENTORY.replace("    last_rotated: 2026-01-14\n", "")
        errors = self.make(inventory=inventory).errors()
        self.assertTrue(any("manquant(s) : last_rotated" in e for e in errors), errors)

    def test_bad_and_future_dates(self):
        inventory = INVENTORY.replace("2026-01-09", "2026-13-01").replace("2026-01-14", "2026-11-01")
        errors = self.make(inventory=inventory).errors()
        self.assertTrue(any("n'est pas une date" in e for e in errors), errors)
        self.assertTrue(any("dans le futur" in e for e in errors), errors)

    def test_tomorrow_is_tolerated(self):
        # Runner en UTC, rotation datée du jour à Paris juste après minuit.
        inventory = INVENTORY.replace("2026-01-14", "2026-10-29")
        self.assertEqual(self.make(inventory=inventory).errors(), [])

    def test_estimated_must_be_boolean(self):
        errors = self.make(inventory=INVENTORY.replace("estimated: true", "estimated: yes", 1)).errors()
        self.assertTrue(any("estimated doit valoir" in e for e in errors), errors)

    def test_identifier_carries_no_date(self):
        inventory = INVENTORY.replace("    kind: identifier\n", "    kind: identifier\n    last_rotated: 2026-01-01\n")
        errors = self.make(inventory=inventory).errors()
        self.assertTrue(any("un identifiant ne porte ni last_rotated" in e for e in errors), errors)

    def test_broken_links(self):
        inventory = INVENTORY.replace("docs/rb.md#hetzner", "docs/rb.md#ovh").replace("how: docs/rb.md\n", "how: docs/absent.md\n")
        errors = self.make(inventory=inventory).errors()
        self.assertTrue(any("ancre absente" in e for e in errors), errors)
        self.assertTrue(any("fichier introuvable" in e for e in errors), errors)


class DueTest(unittest.TestCase):
    def entry(self, kind, date, key="K"):
        return {"key": key, "file": "f", "kind": kind, "last_rotated": date, "estimated": True, "how": "docs/rb.md"}

    def test_add_months_clamps_the_day(self):
        self.assertEqual(rotation.add_months(datetime.date(2026, 1, 31), 1), datetime.date(2026, 2, 28))
        self.assertEqual(rotation.add_months(datetime.date(2024, 2, 29), 12), datetime.date(2025, 2, 28))
        self.assertEqual(rotation.add_months(datetime.date(2026, 10, 28), 24), datetime.date(2028, 10, 28))

    def test_window(self):
        entries = [
            self.entry("provider", "2025-11-27", "inside"),  # 2026-11-27 : dans 30 jours
            self.entry("provider", "2025-11-28", "outside"),  # 2026-11-28 : dans 31 jours
            self.entry("application", "2024-10-01", "late"),  # 2026-10-01 : dépassée
            self.entry("database", "2000-01-01", "db"),
            self.entry("encryption", "2000-01-01", "enc"),
            {"key": "id", "file": "f", "kind": "identifier"},
        ]
        due = rotation.due_entries(entries, TODAY, 30)
        self.assertEqual([e["key"] for _, e in due], ["late", "inside"])

    def test_report(self):
        status, msg, lines = rotation.report([], TODAY, 30)
        self.assertEqual((status, lines), ("up", []))
        self.assertIn("30 jours", msg)
        due = rotation.due_entries([self.entry("provider", "2025-10-01", "late"), self.entry("provider", "2025-11-20", "soon")], TODAY, 30)
        status, msg, lines = rotation.report(due, TODAY, 30)
        self.assertEqual(status, "down")
        self.assertEqual(msg, "2 secret(s) à faire tourner, 1 en retard : late, soon")
        self.assertIn("échéance 2026-10-01 dépassée (date estimée)", lines[0])
        self.assertIn("échéance 2026-11-20 proche", lines[1])


class SecoursTestTest(unittest.TestCase):
    def test_reads_the_front_matter(self):
        self.assertEqual(rotation.secours_test(SECOURS_RUNBOOK, TODAY), (datetime.date(2026, 10, 20), []))

    def test_rejects_missing_bad_and_future_dates(self):
        cases = {
            "# pas de front matter\n": "front matter",
            "---\nautre: 1\n---\n": "dernier_test: AAAA-MM-JJ",
            "---\ndernier_test: 2026-10-20\ndernier_test: 2026-10-21\n---\n": "dernier_test: AAAA-MM-JJ",
            "---\ndernier_test: hier\n---\n": "n'est pas une date",
            "---\ndernier_test: 2026-11-28\n---\n": "dans le futur",
            "---\ndernier_test: 2026-10-20\n": "front matter",
        }
        for text, message in cases.items():
            with self.subTest(text=text):
                date, errors = rotation.secours_test(text, TODAY)
                self.assertIsNone(date)
                self.assertIn(message, errors[0])

    def test_a_line_outside_the_front_matter_does_not_count(self):
        self.assertIsNone(rotation.secours_test("---\n---\ndernier_test: 2026-10-20\n", TODAY)[0])

    def test_overdue_after_100_days(self):
        date = datetime.date(2026, 7, 20)
        self.assertIsNone(rotation.secours_overdue(date, date + datetime.timedelta(days=100)))
        self.assertIn("101 jours", rotation.secours_overdue(date, date + datetime.timedelta(days=101)))


class MainTest(unittest.TestCase):
    def setUp(self):
        self.repo = Repo()
        self.addCleanup(self.repo.close)

    def run_main(self, argv, env=None):
        out = io.StringIO()
        with mock.patch.dict(os.environ, env or {}, clear=True), redirect_stdout(out):
            code = rotation.main(argv, root=self.repo.root)
        return code, out.getvalue()

    def test_check_mode_ok_and_failing(self):
        self.assertEqual(self.run_main(["--today", "2026-10-28"])[0], 0)
        (self.repo.root / "secrets.sops.yaml").write_text(ROOT_SOPS.replace("sops:", "NEW: x\nsops:"), encoding="utf-8")
        code, out = self.run_main(["--today", "2026-10-28"])
        self.assertEqual(code, 1)
        self.assertIn("::error::secrets.sops.yaml : la clé NEW manque", out)

    def test_stray_sops_file(self):
        (self.repo.root / "tofu/x").mkdir(parents=True)
        (self.repo.root / "tofu/x/secrets.sops.yaml").write_text(ROOT_SOPS, encoding="utf-8")
        (self.repo.root / ".terraform").mkdir()
        (self.repo.root / ".terraform/secrets.sops.yaml").write_text(ROOT_SOPS, encoding="utf-8")
        code, out = self.run_main(["--today", "2026-10-28"])
        self.assertEqual(code, 1)
        self.assertIn("::error::tofu/x/secrets.sops.yaml : fichier SOPS hors de SOPS_FILES", out)
        self.assertNotIn(".terraform", out)

    def test_due_pushes_up(self):
        with mock.patch.object(rotation, "push") as push:
            code, _ = self.run_main(["--due", "--today", "2026-10-28"], {"PUSH_URL": "https://kuma.test/api/push/x"})
        self.assertEqual(code, 0)
        push.assert_called_once_with("https://kuma.test/api/push/x", "up", "aucun secret à faire tourner dans les 30 jours")

    def test_due_pushes_down_with_names(self):
        summary = self.repo.root / "summary.md"
        with mock.patch.object(rotation, "push") as push:
            code, out = self.run_main(["--due", "--today", "2026-12-15"], {"PUSH_URL": "https://kuma.test/x", "GITHUB_STEP_SUMMARY": str(summary)})
        self.assertEqual(code, 1)
        self.assertEqual(push.call_args.args[1:], ("down", "1 secret(s) à faire tourner, 0 en retard : HCLOUD_TOKEN"))
        self.assertIn("HCLOUD_TOKEN (secrets.sops.yaml, provider) : échéance 2027-01-09 proche", out)
        self.assertIn("HCLOUD_TOKEN", summary.read_text(encoding="utf-8"))

    def test_invalid_inventory_pushes_down(self):
        (self.repo.root / rotation.INVENTORY).write_text("nope\n", encoding="utf-8")
        with mock.patch.object(rotation, "push") as push:
            code, _ = self.run_main(["--due", "--today", "2026-10-28"], {"PUSH_URL": "https://kuma.test/x"})
        self.assertEqual(code, 1)
        self.assertEqual(push.call_args.args[1], "down")
        self.assertIn("invalide", push.call_args.args[2])

    def test_push_error_hides_the_url(self):
        with mock.patch.object(rotation, "push", side_effect=OSError("https://kuma.test/api/push/SECRET")):
            code, out = self.run_main(["--due", "--today", "2026-10-28"], {"PUSH_URL": "https://kuma.test/api/push/SECRET"})
        self.assertEqual(code, 1)
        self.assertNotIn("SECRET", out)

    def test_missing_secours_runbook_fails_lint_with_the_other_errors(self):
        (self.repo.root / rotation.SECOURS_TEST).unlink()
        (self.repo.root / "secrets.sops.yaml").write_text(ROOT_SOPS.replace("sops:", "NEW: x\nsops:"), encoding="utf-8")
        code, out = self.run_main(["--today", "2026-10-28"])
        self.assertEqual(code, 1)
        self.assertIn(f"::error::{rotation.SECOURS_TEST} illisible", out)
        self.assertIn("la clé NEW manque", out)

    def test_overdue_secours_test_pushes_down(self):
        (self.repo.root / rotation.SECOURS_TEST).write_text(SECOURS_RUNBOOK.replace("2026-10-20", "2026-07-19"), encoding="utf-8")
        with mock.patch.object(rotation, "push") as push:
            code, out = self.run_main(["--due", "--today", "2026-10-28"], {"PUSH_URL": "https://kuma.test/x"})
        self.assertEqual(code, 1)
        self.assertEqual(push.call_args.args[1:], ("down", "test de la clé secours en retard (101 j)"))
        self.assertIn(rotation.SECOURS_TEST, out)

    def test_overdue_secours_test_joins_due_secrets(self):
        with mock.patch.object(rotation, "push") as push:
            self.run_main(["--due", "--today", "2027-02-15"], {"PUSH_URL": "https://kuma.test/x"})
        status, msg = push.call_args.args[1:]
        self.assertEqual(status, "down")
        self.assertTrue(msg.startswith("test de la clé secours en retard (118 j) ; 1 secret(s)"), msg)

    def test_no_push_url_only_warns(self):
        with mock.patch.object(rotation, "push") as push:
            code, out = self.run_main(["--due", "--today", "2026-10-28"])
        self.assertEqual(code, 0)
        push.assert_not_called()
        self.assertIn("PUSH_URL vide", out)


if __name__ == "__main__":
    unittest.main()
