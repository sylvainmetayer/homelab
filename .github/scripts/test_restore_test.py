"""Tests of the --verify-data mode of restore_test.py (Lint workflow:
python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""
import json
import os
import subprocess
import unittest
from unittest import mock

import restore_test as rt

ENTRY = {"host": "docker", "repo": "wiki", "role": "wiki"}
SUMMARY = ("Finished cryptographic data integrity verification, "
           "verified {chunks} chunks with {errors} integrity errors.")


def listing(stamp, name="wiki-1"):
    stdout = json.dumps({"archives": [{"name": name}], "repository": {"last_modified": stamp}})
    return subprocess.CompletedProcess([], 0, stdout, "")


def check(returncode, stderr):
    return subprocess.CompletedProcess([], returncode, "", stderr)


class VerifyData(unittest.TestCase):
    def verify(self, *results):
        calls = []

        def fake_run(*args, **kwargs):
            calls.append((args, kwargs))
            result = results[len(calls) - 1]
            if isinstance(result, Exception):
                raise result
            return result

        with mock.patch.dict(os.environ, {"BORG_REPO_BASE": "ssh://u@h:23/."}), \
                mock.patch.object(rt, "run", side_effect=fake_run):
            try:
                return rt.verify_data(ENTRY), calls
            finally:
                self.assertEqual(len(calls), len(results))

    def test_clean_check(self):
        message, calls = self.verify(
            listing("t1"),
            check(0, "Analyzing archive wiki-1 (1/1)\n" + SUMMARY.format(chunks=1234, errors=0)))
        self.assertIn("1234 blocs vérifiés", message)
        borg_check = calls[1]
        self.assertEqual(borg_check[0][:3], ("borg", "check", "--bypass-lock"))
        self.assertIn("--verify-data", borg_check[0])
        self.assertIn("--archives-only", borg_check[0])
        self.assertNotIn("--repair", borg_check[0])
        self.assertTrue(borg_check[1]["quiet"])
        self.assertEqual(borg_check[0][-1], "ssh://u@h:23/./docker/wiki")

    def test_errors_hide_borg_output(self):
        stderr = "archive wiki-1: /secret/path: New missing file chunk detected\n" \
                 + SUMMARY.format(chunks=10, errors=2)
        with self.assertRaises(rt.RestoreError) as raised:
            self.verify(listing("t1"), check(1, stderr), listing("t1"))
        self.assertIn("2 blocs corrompus sur 10", str(raised.exception))
        self.assertNotIn("/secret/path", str(raised.exception))

    def test_crash_without_summary(self):
        with self.assertRaises(rt.RestoreError) as raised:
            self.verify(listing("t1"), check(2, "Traceback /secret/path"), listing("t1"))
        self.assertIn("sortie masquée", str(raised.exception))
        self.assertNotIn("/secret/path", str(raised.exception))

    def test_backup_during_check_is_inconclusive(self):
        with self.assertRaises(rt.RestoreError) as raised:
            self.verify(listing("t1"), check(1, "orphaned objects found"), listing("t2", name="wiki-2"))
        self.assertIn("non concluant", str(raised.exception))

    def test_prune_during_check_is_inconclusive(self):
        # Same latest archive, older one pruned: only the manifest's timestamp moved.
        with self.assertRaises(rt.RestoreError) as raised:
            self.verify(listing("t1"), check(1, "missing chunk"), listing("t2"))
        self.assertIn("non concluant", str(raised.exception))

    def test_archive_error_without_integrity_error(self):
        with self.assertRaises(rt.RestoreError) as raised:
            self.verify(listing("t1"), check(1, SUMMARY.format(chunks=10, errors=0)), listing("t1"))
        self.assertNotIn("0 blocs corrompus", str(raised.exception))
        self.assertIn("erreur dans les archives", str(raised.exception))

    def test_failed_listing_keeps_the_check_failure(self):
        with self.assertRaises(rt.RestoreError) as raised:
            self.verify(listing("t1"), check(1, SUMMARY.format(chunks=10, errors=2)),
                        rt.RestoreError("borg list a échoué (2): Connection closed"))
        self.assertIn("2 blocs corrompus sur 10", str(raised.exception))

    def test_success_needs_the_summary(self):
        with self.assertRaises(rt.RestoreError):
            self.verify(listing("t1"), check(0, ""))


class Main(unittest.TestCase):
    def test_usage(self):
        with mock.patch("sys.stderr"):
            self.assertEqual(rt.main([]), 2)
            self.assertEqual(rt.main(["--verify-data"]), 2)
            self.assertEqual(rt.main(["a", "b"]), 2)


if __name__ == "__main__":
    unittest.main()
