"""Tests of maintenance_ics.py: rotation due dates, cron rules, DNS zones,
rendering and validation of the calendar (Lint workflow: python -I -m
unittest discover -s .github/scripts -p 'test_*.py')."""

import datetime
import io
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

import maintenance_ics as ics

NOW = datetime.datetime(2026, 10, 28, 12, 0, tzinfo=datetime.timezone.utc)

INVENTORY = """\
secrets:
  - key: HCLOUD_TOKEN
    file: secrets.sops.yaml
    kind: provider
    last_rotated: 2026-01-09
    estimated: true
    how: docs/rb.md#hetzner
  - key: OVH_APPLICATION_KEY
    file: secrets.sops.yaml
    kind: provider
    last_rotated: 2026-01-09
    estimated: false
    how: docs/rb.md#ovh
  - key: wiki_admin_password
    file: ansible/secrets.sops.yaml
    kind: application
    last_rotated: 2024-02-29
    estimated: false
    how: docs/rb.md
  - key: wiki_db_password
    file: ansible/secrets.sops.yaml
    kind: database
    last_rotated: 2020-01-01
    estimated: true
    how: docs/rb.md
  - key: home_ip
    file: secrets.sops.yaml
    kind: identifier
"""
RESTORE = """\
on:
  schedule:
    - cron: "0 10 1,15 * *"
"""
BORG = """\
on:
  schedule:
    - cron: '0 2 5 1,4,7,10 *'
"""
DNS_PANGOLIN = """\
resource "ovh_domain_zone_record" "a" {
  zone      = "sylvain.cloud"
  subdomain = "*"
}
"""
DNS_MAIL = """\
locals {
  spf_records = {
    "sylvainmetayer.fr" = "v=spf1 -all"
    "metayer.dev"       = "v=spf1 -all"
  }
  hosts = {
    "media.sylvain.cloud" = "192.168.1.10"
  }
  target = "1.2.3.4"
}
"""


class RepoMixin:
    def make_repo(self, restore=RESTORE):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        files = {
            "secrets-rotation.yaml": INVENTORY,
            ".github/workflows/restore-test.yaml": restore,
            ".github/workflows/borg-check.yaml": BORG,
            "tofu/dns/pangolin.tf": DNS_PANGOLIN,
            "tofu/dns/mail.tf": DNS_MAIL,
        }
        for path, text in files.items():
            (root / path).parent.mkdir(parents=True, exist_ok=True)
            (root / path).write_text(text, encoding="utf-8")
        return root


class RotationEventsTest(RepoMixin, unittest.TestCase):
    def test_groups_keys_by_deadline_with_the_rotation_cadence(self):
        events = ics.rotation_events(self.make_repo())
        self.assertEqual([event["date"] for event in events], [datetime.date(2026, 2, 28), datetime.date(2027, 1, 9)])
        leap, provider = events
        # 2024-02-29 + 24 mois : le 28 février, comme check_secret_rotation.
        self.assertIn("wiki_admin_password", leap["summary"])
        self.assertEqual(provider["summary"], "Rotation des secrets (2) : HCLOUD_TOKEN, OVH_APPLICATION_KEY")
        self.assertIn("date estimée", provider["description"])
        self.assertIn("https://github.com/sylvainmetayer/homelab/blob/main/docs/rb.md#ovh", provider["description"])
        self.assertEqual(provider["uid"], "rotation-2027-01-09@homelab.sylvain.dev")

    def test_skips_kinds_without_a_period(self):
        text = "".join(event["description"] for event in ics.rotation_events(self.make_repo()))
        self.assertNotIn("wiki_db_password", text)
        self.assertNotIn("home_ip", text)

    def test_uses_the_rotation_module_periods(self):
        self.assertIs(ics.rotation, sys.modules["check_secret_rotation"])
        self.assertEqual(ics.rotation.KINDS["provider"], 12)


class CronTest(RepoMixin, unittest.TestCase):
    def test_monthly_and_quarterly(self):
        self.assertEqual(ics.cron_rule("0 10 1,15 * *"), (10, 0, "FREQ=MONTHLY;BYMONTHDAY=1,15"))
        self.assertEqual(ics.cron_rule("30 2 5 1,4,7,10 *"), (2, 30, "FREQ=YEARLY;BYMONTH=1,4,7,10;BYMONTHDAY=5"))

    def test_refuses_what_it_cannot_translate(self):
        for expression in ("0 10 * * 1", "*/5 10 1 * *", "0 10 1-7 * *", "0 10 1 */3 *", "0 10 1 *"):
            with self.subTest(expression=expression), self.assertRaises(ics.CalendarError):
                ics.cron_rule(expression)

    def test_first_occurrence_is_on_the_rule(self):
        self.assertEqual(ics.first_occurrence("FREQ=YEARLY;BYMONTH=4,7;BYMONTHDAY=5"), datetime.date(2026, 4, 5))
        self.assertEqual(ics.first_occurrence("FREQ=MONTHLY;BYMONTHDAY=15"), datetime.date(2026, 1, 15))

    def test_scheduled_events_read_the_workflows(self):
        restore, borg = ics.scheduled_events(self.make_repo())
        self.assertEqual(restore["rrule"], "FREQ=MONTHLY;BYMONTHDAY=1,15")
        self.assertEqual(restore["start"], datetime.datetime(2026, 1, 1, 10, 0))
        self.assertEqual(borg["start"], datetime.datetime(2026, 1, 5, 2, 0))

    def test_a_trailing_comment_is_allowed(self):
        (restore, _) = ics.scheduled_events(self.make_repo(restore='    - cron: "0 10 1,15 * *"  # UTC\n'))
        self.assertEqual(restore["rrule"], "FREQ=MONTHLY;BYMONTHDAY=1,15")

    def test_a_workflow_without_one_cron_fails(self):
        with self.assertRaises(ics.CalendarError):
            ics.scheduled_events(self.make_repo(restore="on: push\n"))


class DomainTest(RepoMixin, unittest.TestCase):
    def test_zones_and_zone_map_keys(self):
        self.assertEqual(ics.domains(self.make_repo()), ["metayer.dev", "sylvain.cloud", "sylvainmetayer.fr"])

    def test_unknown_expiry_falls_in_the_yearly_todo(self):
        (event,) = ics.domain_events(self.make_repo())
        self.assertEqual(event["date"], datetime.date(2026, 12, 1))
        self.assertIn("TODO", event["description"])

    def test_known_expiry_gets_its_own_reminder(self):
        original = dict(ics.DOMAIN_EXPIRY)
        self.addCleanup(lambda: (ics.DOMAIN_EXPIRY.clear(), ics.DOMAIN_EXPIRY.update(original)))
        ics.DOMAIN_EXPIRY.update({"metayer.dev": "03-15"})
        events = ics.domain_events(self.make_repo())
        self.assertEqual(events[0]["uid"], "domain-metayer.dev@homelab.sylvain.dev")
        self.assertEqual(events[0]["date"], datetime.date(2026, 2, 13))
        self.assertNotIn("metayer.dev", events[1]["description"])


class RenderTest(RepoMixin, unittest.TestCase):
    def test_built_calendar_is_valid(self):
        text = ics.build(self.make_repo(), now=NOW)
        self.assertEqual(ics.validate(text), [])
        self.assertIn("DTSTAMP:20261028T120000Z\r\n", text)
        self.assertIn("DTSTART;VALUE=DATE:20270109\r\n", text)
        self.assertIn("TRIGGER:-P7D\r\n", text)
        self.assertEqual(text.count("BEGIN:VEVENT"), 5)

    def test_fold_and_escape(self):
        line = "DESCRIPTION:" + ics.escape("é, ; \\ \n") * 20
        folded = ics.fold(line)
        self.assertTrue(all(len(part.encode()) <= 75 for part in folded.split("\r\n")))
        self.assertEqual(folded.replace("\r\n ", ""), line)
        self.assertEqual(ics.escape("a,b;c\\d\ne"), "a\\,b\\;c\\\\d\\ne")

    def test_validate_reports_broken_calendars(self):
        good = ics.build(self.make_repo(), now=NOW)
        self.assertIn("fins de ligne autres que CRLF", ics.validate(good.replace("\r\n", "\n")))
        uid = "UID:restore-test@homelab.sylvain.dev\r\n"
        self.assertIn("VEVENT sans UID", ics.validate(good.replace(uid, "")))
        borg = "UID:borg-check@homelab.sylvain.dev"
        self.assertIn("UID en double : restore-test@homelab.sylvain.dev", ics.validate(good.replace(borg, uid.strip())))
        self.assertIn("composants non fermés : VCALENDAR", ics.validate(good.replace("END:VCALENDAR\r\n", "")))
        self.assertIn("ligne 1 : plus de 75 octets", ics.validate("X" * 76 + "\r\n"))
        # Un composant fermé hors d'ordre est signalé, sans IndexError.
        self.assertTrue(ics.validate("BEGIN:VEVENT\r\nEND:VCALENDAR\r\nUID:x\r\n"))

    def test_main_writes_the_file(self):
        root = self.make_repo()
        out = root / "site" / "maintenance.ics"
        with redirect_stdout(io.StringIO()):
            self.assertEqual(ics.main(["--output", str(out)], root=root), 0)
        self.assertEqual(ics.validate(out.read_bytes().decode()), [])

    def test_main_fails_on_a_bad_source(self):
        root = self.make_repo(restore="on: push\n")
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            self.assertEqual(ics.main(["--check"], root=root), 1)
        self.assertIn("::error::", buffer.getvalue())


class IsolatedRunTest(unittest.TestCase):
    def test_runs_under_python_isolated_mode(self):
        script = Path(ics.__file__).resolve()
        result = subprocess.run(  # NOSONAR: le script du dépôt, sans shell ni entrée externe
            [sys.executable, "-I", str(script), "--check"], capture_output=True, text=True, check=False, cwd=script.parents[2]
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
