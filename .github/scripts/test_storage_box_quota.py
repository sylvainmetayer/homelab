"""Tests of storage_box_quota.py: reading the Hetzner API answer, threshold
(Lint workflow: python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""

import datetime
import http.client
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
                "id": 42,
                "name": name,
                "storage_box_type": {"name": "bx11", "size": quota},
                "stats": {"size": used, "size_data": used - snapshots, "size_snapshots": snapshots},
            }
        ]
    }


NOW = datetime.datetime(2026, 11, 11, 12, 0, tzinfo=datetime.timezone.utc)


def snapshots(count=9, last_hours=9):
    """`count` snapshots quotidiens, le plus récent vieux de `last_hours` h."""
    return {
        "snapshots": [
            {"created": (NOW - datetime.timedelta(hours=last_hours + 24 * i)).strftime("%Y-%m-%dT%H:%M:%SZ")}
            for i in range(count)
        ]
    }


def fresh():
    """Neuf snapshots dont le dernier date d'une heure, face à l'heure réelle."""
    now = datetime.datetime.now(datetime.timezone.utc)
    return {"snapshots": [{"created": (now - datetime.timedelta(hours=1 + 24 * i)).isoformat()} for i in range(9)]}


class SnapshotsTest(unittest.TestCase):
    def test_nine_recent_snapshots_are_up(self):
        status, msg = storage_box_quota.evaluate_snapshots(snapshots(), NOW)
        self.assertEqual(status, "up")
        self.assertIn("9 snapshots", msg)

    def test_seven_is_enough_six_is_not(self):
        self.assertEqual(storage_box_quota.evaluate_snapshots(snapshots(7), NOW)[0], "up")
        status, msg = storage_box_quota.evaluate_snapshots(snapshots(6), NOW)
        self.assertEqual(status, "down")
        self.assertIn("6 snapshot(s)", msg)

    def test_old_latest_is_down(self):
        self.assertEqual(storage_box_quota.evaluate_snapshots(snapshots(last_hours=48), NOW)[0], "up")
        status, msg = storage_box_quota.evaluate_snapshots(snapshots(last_hours=49), NOW)
        self.assertEqual(status, "down")
        self.assertIn("49 h", msg)

    def test_no_snapshot_is_down(self):
        self.assertEqual(storage_box_quota.evaluate_snapshots({"snapshots": []}, NOW)[0], "down")

    def test_malformed_is_an_error(self):
        for data in ([], {}, {"snapshots": None}, {"snapshots": [{}]}, {"snapshots": [{"created": "hier"}]}):
            with self.subTest(data=data), self.assertRaises(storage_box_quota.QuotaError):
                storage_box_quota.evaluate_snapshots(data, NOW)

    def test_box_id(self):
        self.assertEqual(storage_box_quota.box_id(payload(1), "backups"), 42)
        with self.assertRaises(storage_box_quota.QuotaError):
            storage_box_quota.box_id({"storage_boxes": [{"name": "backups"}]}, "backups")


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

    def test_malformed_payload_is_an_error(self):
        # Une réponse inattendue pousse « down » : jamais une trace sans push.
        for data in ([], {"storage_boxes": None}, {"storage_boxes": ["x"]}, {"storage_boxes": [{}]}):
            with self.subTest(data=data), self.assertRaises(storage_box_quota.QuotaError):
                storage_box_quota.evaluate(data, "backups", 80)

    def test_threshold_is_printed_as_given(self):
        self.assertIn("seuil 80 %", storage_box_quota.evaluate(payload(1), "backups", 80.0)[1])

    def test_zero_quota_is_an_error(self):
        with self.assertRaises(storage_box_quota.QuotaError):
            storage_box_quota.evaluate(payload(1, quota=0), "backups", 80)


class MainTest(unittest.TestCase):
    def run_main(self, fetched, env=None, snaps=None):
        pushes = []
        environ = {"HCLOUD_READONLY_TOKEN": "fake-token", "PUSH_URL": "https://uptime.example.test/api/push/x"}
        environ.update(env or {})
        with (
            mock.patch.dict(os.environ, environ, clear=True),
            mock.patch.object(storage_box_quota, "fetch", side_effect=fetched),
            mock.patch.object(storage_box_quota, "fetch_snapshots", side_effect=lambda *a: snaps or fresh()),
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

    def test_stale_snapshots_push_down_though_the_quota_is_fine(self):
        rc, pushes, _ = self.run_main(lambda *a: payload(TIB // 4), snaps={"snapshots": []})
        self.assertEqual(rc, 1)
        self.assertEqual(pushes[0][1], "down")
        self.assertIn("aucun snapshot", pushes[0][2])

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

    def test_truncated_answer_pushes_down(self):
        def fail(*_):
            raise http.client.IncompleteRead(b"{")

        rc, pushes, _ = self.run_main(fail)
        self.assertEqual(rc, 1)
        self.assertEqual(pushes[0][1], "down")

    def test_push_failure_fails_without_the_url(self):
        url = "https://uptime.example.test/api/push/x"
        with (
            mock.patch.dict(os.environ, {"HCLOUD_READONLY_TOKEN": "fake-token", "PUSH_URL": url}, clear=True),
            mock.patch.object(storage_box_quota, "fetch", side_effect=lambda *a: payload(1)),
            mock.patch.object(storage_box_quota, "fetch_snapshots", side_effect=lambda *a: fresh()),
            mock.patch.object(storage_box_quota, "push", side_effect=http.client.InvalidURL(url)),
            mock.patch("sys.stdout", new_callable=io.StringIO) as stdout,
        ):
            rc = storage_box_quota.main([])
        self.assertEqual(rc, 1)
        self.assertNotIn(url, stdout.getvalue())

    def test_summary_is_written(self):
        with tempfile.NamedTemporaryFile("r", encoding="utf-8", suffix=".md") as summary:
            self.run_main(lambda *a: payload(TIB // 4), env={"GITHUB_STEP_SUMMARY": summary.name})
            self.assertIn("25.0 %", summary.read())


if __name__ == "__main__":
    unittest.main()
