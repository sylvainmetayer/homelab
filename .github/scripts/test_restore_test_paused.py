"""Tests of the archive age check of restore_test.py and of "paused" entries
(Lint workflow: python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""
import datetime
import json
import pathlib
import unittest

import restore_test as rt

ENTRY = {"host": "docker", "repo": "paperless", "role": "paperless_ngx"}
OLD = rt.MAX_ARCHIVE_AGE + datetime.timedelta(days=30)
FRESH = rt.MAX_ARCHIVE_AGE - datetime.timedelta(hours=1)


class CheckAge(unittest.TestCase):
    def test_fresh_archive_passes(self):
        rt.check_age(ENTRY, "paperless-1", FRESH)

    def test_old_archive_fails(self):
        with self.assertRaisesRegex(rt.RestoreError, "ne tourne plus"):
            rt.check_age(ENTRY, "paperless-1", OLD)

    def test_old_archive_of_a_paused_app_passes(self):
        rt.check_age({**ENTRY, "paused": True}, "paperless-1", OLD)

    def test_paused_false_still_checks_the_age(self):
        with self.assertRaises(rt.RestoreError):
            rt.check_age({**ENTRY, "paused": False}, "paperless-1", OLD)


class Manifest(unittest.TestCase):
    # The workflow runs jq on it; the format is checked here too, since a
    # "paused": "false" string would pass for true in Tofu's lookup().
    def test_paused_is_a_boolean_where_set(self):
        manifest = json.loads((pathlib.Path(__file__).parents[1] / "restore-test" / "apps.json").read_text())
        for app, entry in manifest.items():
            with self.subTest(app=app):
                self.assertIsInstance(entry.get("paused", False), bool)


if __name__ == "__main__":
    unittest.main()
