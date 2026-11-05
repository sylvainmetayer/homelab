"""Tests de smart_check.py (rôle smart_check), lancés par verify.yml du
scénario avec le python3 de l'hôte de test. À la main : copier ce fichier à
côté de ansible/roles/smart_check/files/smart_check.py, puis
python3 -I -m unittest discover -s . -p 'test_*.py'.
"""

import http.client
import io
import json
import os
import tempfile
import types
import unittest
import urllib.request
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

import smart_check as sc


def hdd(pending=0, uncorrectable=0, reallocated=0, crc=0, passed=True, serial="HDD1"):
    return {
        "smart_status": {"passed": passed}, "model_name": "WD", "serial_number": serial,
        "device": {"name": "/dev/sdc"}, "rotation_rate": 5400,
        "ata_smart_attributes": {"table": [
            {"id": 5, "name": "Reallocated_Sector_Ct", "value": 100, "raw": {"value": reallocated}},
            {"id": 197, "name": "Current_Pending_Sector", "value": 100, "raw": {"value": pending}},
            {"id": 198, "name": "Offline_Uncorrectable", "value": 100, "raw": {"value": uncorrectable}},
            {"id": 199, "name": "UDMA_CRC_Error_Count", "value": 200, "raw": {"value": crc}},
        ]},
    }


def ssd(wear, rotation=0):
    return {
        "smart_status": {"passed": True}, "model_name": "SSD", "serial_number": "SSD1",
        "device": {"name": "/dev/sda"}, "rotation_rate": rotation,
        "ata_smart_attributes": {"table": [
            {"id": 177, "name": "Wear_Leveling_Count", "value": wear, "raw": {"value": 0}},
            {"id": 232, "name": "Available_Reservd_Space", "value": 100, "raw": {"value": 100}},
        ]},
    }


def nvme(used=3, spare=100, errors=0):
    return {
        "smart_status": {"passed": True}, "model_name": "NVME", "serial_number": "N1",
        "device": {"name": "/dev/sda"},
        "nvme_smart_health_information_log": {"percentage_used": used, "available_spare": spare, "media_errors": errors},
    }


def keys(data):
    return {f["key"]: f for f in sc.inspect(data)}


class InspectTest(unittest.TestCase):
    def test_healthy_disks_have_no_finding(self):
        for data in (hdd(), ssd(100), nvme()):
            self.assertEqual(sc.inspect(data), [])

    def test_failed_verdict(self):
        self.assertEqual(keys(hdd(passed=False))["verdict"]["priority"], 5)

    def test_pending_and_uncorrectable_sectors_are_urgent_at_any_count(self):
        found = keys(hdd(pending=1, uncorrectable=1))
        self.assertEqual((found["attr197"]["priority"], found["attr198"]["priority"]), (5, 5))

    def test_reallocated_and_crc_are_counters_to_buy_or_replace(self):
        found = keys(hdd(reallocated=8, crc=3))
        self.assertEqual((found["attr5"]["level"], found["attr199"]["level"]), (8, 3))
        self.assertEqual(found["attr199"]["priority"], 4)

    def test_ssd_wear_thresholds(self):
        self.assertEqual(keys(ssd(20)), {})
        self.assertEqual((keys(ssd(19))["wear177"]["level"], keys(ssd(19))["wear177"]["priority"]), (1, 4))
        self.assertEqual((keys(ssd(10))["wear177"]["level"], keys(ssd(10))["wear177"]["priority"]), (1, 4))
        self.assertEqual((keys(ssd(9))["wear177"]["level"], keys(ssd(9))["wear177"]["priority"]), (2, 5))

    def test_a_hard_disk_has_no_wear_attribute(self):
        self.assertEqual(keys(ssd(5, rotation=7200)), {})

    def test_nvme_thresholds(self):
        self.assertEqual(keys(nvme(used=80, spare=20)), {})
        self.assertEqual(keys(nvme(used=81))["used"]["priority"], 4)
        self.assertEqual(keys(nvme(spare=19))["spare"]["priority"], 5)
        self.assertEqual(keys(nvme(errors=2))["media_errors"]["level"], 2)


def fake_smartctl(disks):
    """subprocess.run remplacé : le JSON de chaque chemin (ou rien)."""
    def run(argv, **_kwargs):
        data = disks.get(argv[-1])
        return types.SimpleNamespace(stdout=json.dumps(data) if data is not None else "", returncode=4)
    return mock.patch.object(sc.subprocess, "run", run)


class CheckTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.args = types.SimpleNamespace(
            host="nas", state_file=os.path.join(self.dir.name, "state.json"),
            device=["/dev/sdc"], smartctl="smartctl",
        )

    def run_check(self, data):
        with fake_smartctl({"/dev/sdc": data}):
            return sc.check(self.args)

    def test_first_sighting_is_announced_then_silent_until_it_rises(self):
        notification, state, summary, unreadable = self.run_check(hdd(pending=2167, uncorrectable=2031))
        self.assertEqual(notification["priority"], 5)
        self.assertIn("197 en attente : 2167", notification["message"])
        self.assertEqual(unreadable, [])
        sc.save_state(self.args.state_file, state)

        notification, state, summary, _ = self.run_check(hdd(pending=2167, uncorrectable=2031))
        self.assertIsNone(notification)
        self.assertIn("2 constat(s)", summary)

        notification, state, _, _ = self.run_check(hdd(pending=2300, uncorrectable=2031))
        self.assertIn("197 en attente : 2300 (annoncé à 2167)", notification["message"])
        self.assertNotIn("198", notification["message"])

    def test_a_counter_going_down_keeps_its_high_water_mark(self):
        _, state, _, _ = self.run_check(hdd(pending=100))
        sc.save_state(self.args.state_file, state)
        notification, state, _, _ = self.run_check(hdd(pending=40))
        self.assertIsNone(notification)
        sc.save_state(self.args.state_file, state)
        notification, _, _, _ = self.run_check(hdd(pending=60))
        self.assertIsNone(notification)

    def test_a_finding_that_went_away_rings_again_on_relapse(self):
        _, state, _, _ = self.run_check(hdd(pending=100))
        sc.save_state(self.args.state_file, state)
        _, state, _, _ = self.run_check(hdd())
        sc.save_state(self.args.state_file, state)
        notification, _, _, _ = self.run_check(hdd(pending=3))
        self.assertIsNotNone(notification)

    def test_empty_attributes_are_unreadable_not_healthy(self):
        data = hdd()
        data["ata_smart_attributes"] = {"table": []}
        _, _, _, unreadable = self.run_check(data)
        self.assertEqual(len(unreadable), 1)

    def test_state_is_per_serial_not_per_path(self):
        _, state, _, _ = self.run_check(hdd(pending=5, serial="A"))
        sc.save_state(self.args.state_file, state)
        notification, _, _, _ = self.run_check(hdd(pending=5, serial="B"))
        self.assertIsNotNone(notification)

    def test_healthy_summary(self):
        notification, state, summary, _ = self.run_check(hdd())
        self.assertIsNone(notification)
        self.assertEqual(summary, "1 disque(s) lus, rien à signaler")

    def test_unreadable_disk_is_reported_and_others_still_read(self):
        self.args.device = ["/dev/sdc", "/dev/sdd:sat"]
        with fake_smartctl({"/dev/sdc": hdd(pending=1)}):
            notification, _, _, unreadable = sc.check(self.args)
        self.assertIsNotNone(notification)
        self.assertEqual(len(unreadable), 1)
        self.assertIn("/dev/sdd illisible", unreadable[0])

    def test_malformed_state_entries_are_dropped(self):
        with open(self.args.state_file, "w", encoding="utf-8") as handle:
            json.dump({"HDD1": [1], "HDD2": {"attr197": 5}}, handle)
        self.assertEqual(sc.load_state(self.args.state_file), {"HDD2": {"attr197": 5}})

    def test_corrupt_state_is_ignored(self):
        with open(self.args.state_file, "w", encoding="utf-8") as handle:
            handle.write("pas du json")
        self.assertEqual(sc.load_state(self.args.state_file), {})


def answering_302(seen):
    """Vrai urllib, sans réseau : tout répond 302 vers /arrivee, qui répond 200."""
    def http_open(_handler, request):
        seen.append((request.full_url, request.get_header("Authorization")))
        headers = http.client.parse_headers(io.BytesIO(b"Location: /arrivee\r\n\r\n"))
        code = 200 if request.full_url.endswith("/arrivee") else 302
        return mock.MagicMock(code=code, msg="x", info=lambda: headers)
    return mock.patch.object(urllib.request.HTTPHandler, "http_open", http_open)


class TransportTest(unittest.TestCase):
    def test_publish_does_not_follow_a_redirect_with_the_token(self):
        seen = []
        with answering_302(seen), self.assertRaises(sc.CheckError) as raised:
            sc.publish("http://ntfy.test", "scripts", "SECRET", {"title": "t"})
        self.assertEqual(len(seen), 1)
        self.assertNotIn("SECRET", str(raised.exception))

    def test_push_treats_a_redirect_as_failed(self):
        seen = []
        with answering_302(seen), redirect_stderr(io.StringIO()):
            self.assertFalse(sc.push("http://kuma.test/api/push/tok", "up", "ok"))
        self.assertEqual(len(seen), 1)

    def test_push_without_url_is_a_success_that_says_so(self):
        err = io.StringIO()
        with redirect_stderr(err):
            self.assertTrue(sc.push("", "up", "ok"))
        self.assertIn("vide", err.getvalue())


class MainTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.argv = [
            "--host", "nas", "--ntfy-url", "http://ntfy.test", "--topic", "scripts",
            "--state-file", os.path.join(self.dir.name, "state.json"), "--device", "/dev/sdc",
        ]

    def run_main(self, data, env, publish=None):
        pushes = []
        with fake_smartctl({"/dev/sdc": data}), \
                mock.patch.dict(os.environ, env, clear=True), \
                mock.patch.object(sc, "publish", publish or (lambda *a: None)), \
                mock.patch.object(sc, "push", lambda url, status, msg: pushes.append((status, msg)) or True), \
                redirect_stdout(io.StringIO()):
            return sc.main(self.argv), pushes

    def test_publish_failure_pushes_down_and_keeps_the_alert_for_next_time(self):
        def failing(*_args):
            raise sc.CheckError("publication ntfy en échec : URLError")
        code, pushes = self.run_main(hdd(pending=1), {"NTFY_TOKEN": "t"}, failing)
        self.assertEqual((code, pushes[0][0]), (1, "down"))
        self.assertFalse(os.path.exists(self.argv[self.argv.index("--state-file") + 1]))

    def test_alert_published_then_state_written_and_up_pushed(self):
        code, pushes = self.run_main(hdd(pending=1), {"NTFY_TOKEN": "t"})
        self.assertEqual((code, pushes[0][0]), (0, "up"))
        self.assertTrue(os.path.exists(self.argv[self.argv.index("--state-file") + 1]))

    def test_an_unexpected_crash_pushes_down(self):
        data = hdd(pending=1)
        del data["ata_smart_attributes"]["table"][1]["id"]
        code, pushes = self.run_main(data, {"NTFY_TOKEN": "t"})
        self.assertEqual((code, pushes[0][0]), (1, "down"))

    def test_failing_push_exits_2(self):
        with fake_smartctl({"/dev/sdc": hdd()}), \
                mock.patch.dict(os.environ, {"NTFY_TOKEN": "t"}, clear=True), \
                mock.patch.object(sc, "push", return_value=False), \
                redirect_stdout(io.StringIO()):
            self.assertEqual(sc.main(self.argv), 2)


if __name__ == "__main__":
    unittest.main()
