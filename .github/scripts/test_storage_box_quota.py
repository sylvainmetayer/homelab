"""Tests of storage_box_quota.py: reading the Hetzner API answer, threshold
(Lint workflow: python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""

import io
import os
import tempfile
import unittest
import urllib.error
from unittest import mock

import storage_box_quota

TIB = 1024**4


def payload(used, quota=TIB, name="backups", snapshots=0):
    return {
        "storage_boxes": [
            {
                "name": name,
                "storage_box_type": {"name": "bx11", "size": quota},
                "stats": {"size": used, "size_data": used - snapshots, "size_snapshots": snapshots},
            }
        ]
    }


class EvaluateTest(unittest.TestCase):
    def test_below_threshold_is_up(self):
        status, msg = storage_box_quota.evaluate(payload(TIB // 2), "backups", 80)
        self.assertEqual(status, "up")
        self.assertIn("50.0 %", msg)

    def test_threshold_reached_is_down(self):
        status, msg = storage_box_quota.evaluate(payload(800, quota=1000), "backups", 80)
        self.assertEqual(status, "down")
        self.assertIn("80.0 %", msg)

    def test_snapshots_count(self):
        # stats.size porte données et snapshots : les snapshots remplissent
        # aussi la box.
        status, msg = storage_box_quota.evaluate(payload(int(TIB * 0.9), snapshots=int(TIB * 0.5)), "backups", 80)
        self.assertEqual(status, "down")
        self.assertIn("snapshots 512 Gio", msg)

    def test_box_picked_by_name(self):
        data = payload(TIB // 10)
        data["storage_boxes"].append(payload(TIB, name="other")["storage_boxes"][0])
        self.assertEqual(storage_box_quota.evaluate(data, "backups", 80)[0], "up")

    def test_missing_box_is_an_error(self):
        with self.assertRaises(storage_box_quota.QuotaError):
            storage_box_quota.evaluate({"storage_boxes": []}, "backups", 80)

    def test_missing_stats_is_an_error(self):
        data = payload(1)
        del data["storage_boxes"][0]["stats"]
        with self.assertRaises(storage_box_quota.QuotaError):
            storage_box_quota.evaluate(data, "backups", 80)

    def test_zero_quota_is_an_error(self):
        with self.assertRaises(storage_box_quota.QuotaError):
            storage_box_quota.evaluate(payload(1, quota=0), "backups", 80)


class MainTest(unittest.TestCase):
    def run_main(self, fetched, env=None):
        pushes = []
        environ = {"HCLOUD_READONLY_TOKEN": "fake-token", "PUSH_URL": "https://uptime.example.test/api/push/x"}
        environ.update(env or {})
        with (
            mock.patch.dict(os.environ, environ, clear=True),
            mock.patch.object(storage_box_quota, "fetch", side_effect=fetched),
            mock.patch.object(storage_box_quota, "push", side_effect=lambda *a: pushes.append(a)),
            mock.patch("sys.stdout", new_callable=io.StringIO) as stdout,
        ):
            rc = storage_box_quota.main([])
        return rc, pushes, stdout.getvalue()

    def test_up_pushes_up_and_succeeds(self):
        rc, pushes, _ = self.run_main(lambda *a: payload(TIB // 4))
        self.assertEqual(rc, 0)
        self.assertEqual(pushes[0][1], "up")

    def test_full_pushes_down_and_fails(self):
        rc, pushes, out = self.run_main(lambda *a: payload(int(TIB * 0.85)))
        self.assertEqual(rc, 1)
        self.assertEqual(pushes[0][1], "down")
        self.assertIn("::error::", out)

    def test_api_error_pushes_down_without_the_token(self):
        def fail(*_):
            raise OSError("https://api.hetzner.com fake-token")

        rc, pushes, out = self.run_main(fail)
        self.assertEqual(rc, 1)
        self.assertEqual(pushes[0][1], "down")
        self.assertNotIn("fake-token", out + pushes[0][2])

    def test_missing_token_pushes_down(self):
        rc, pushes, _ = self.run_main(lambda *a: payload(1), env={"HCLOUD_READONLY_TOKEN": ""})
        self.assertEqual(rc, 1)
        self.assertEqual(pushes[0][1], "down")

    def test_http_error_names_the_status(self):
        def fail(*_):
            raise urllib.error.HTTPError("https://api.hetzner.com", 401, "Unauthorized", {}, io.BytesIO())

        rc, pushes, _ = self.run_main(fail)
        self.assertEqual(rc, 1)
        self.assertIn("HTTP 401", pushes[0][2])

    def test_summary_is_written(self):
        with tempfile.NamedTemporaryFile("r", encoding="utf-8", suffix=".md") as summary:
            self.run_main(lambda *a: payload(TIB // 4), env={"GITHUB_STEP_SUMMARY": summary.name})
            self.assertIn("25.0 %", summary.read())


if __name__ == "__main__":
    unittest.main()
