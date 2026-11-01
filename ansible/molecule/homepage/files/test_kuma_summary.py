"""Tests de kuma_summary.py (rôle homepage), lancés par verify.yml.

Usage : python3 -I -m unittest discover -s <dossier> -p 'test_*.py', le
dossier contenant ce fichier et kuma_summary.py.
"""

import contextlib
import io
import json
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

import kuma_summary

# Extrait de /metrics d'Uptime Kuma 2.x : une étiquette par tag (backup,
# managed_by), des valeurs échappées, les autres jauges ignorées, un dossier
# (group) en panne qui double sa sonde, une sauvegarde en retard, une en
# attente, une sonde push hors sauvegardes et une ligne illisible.
METRICS = """\
# HELP monitor_status Monitor Status (1 = UP, 0= DOWN, 2= PENDING, 3= MAINTENANCE)
# TYPE monitor_status gauge
monitor_status{backup="",managed_by="tofu",monitor_id="1",monitor_name="Backup",monitor_type="group",monitor_url="https://",monitor_hostname="null",monitor_port="null"} 0
monitor_status{backup="",managed_by="tofu",monitor_id="2",monitor_name="Backup Nextcloud",monitor_type="push",monitor_url="https://",monitor_hostname="null",monitor_port="null"} 0
monitor_status{backup="",managed_by="tofu",monitor_id="3",monitor_name="Backup BookStack",monitor_type="push",monitor_url="https://",monitor_hostname="null",monitor_port="null"} 1
monitor_status{backup="",managed_by="tofu",monitor_id="4",monitor_name="Backup Pangolin",monitor_type="push",monitor_url="https://",monitor_hostname="null",monitor_port="null"} 2
monitor_status{managed_by="tofu",monitor_id="5",monitor_name="Wiki \\"BookStack\\" \\\\ prod",monitor_type="http",monitor_url="https://wiki.example.invalid",monitor_hostname="null",monitor_port="null"} 1
monitor_status{managed_by="tofu",monitor_id="6",monitor_name="Cron DNS",monitor_type="push",monitor_url="https://",monitor_hostname="null",monitor_port="null"} 0
monitor_status{monitor_id="7",monitor_name="Pas fermé} 1
monitor_response_time{monitor_id="5",monitor_name="Wiki",monitor_type="http",monitor_url="https://",monitor_hostname="null",monitor_port="null"} 42
monitor_uptime_ratio{window="1d",monitor_id="5",monitor_name="Wiki",monitor_type="http",monitor_url="https://",monitor_hostname="null",monitor_port="null"} 1
"""


class ParseTest(unittest.TestCase):
    def test_reads_only_monitor_status(self):
        monitors = kuma_summary.parse_monitors(METRICS)
        self.assertEqual([monitor["name"] for monitor in monitors], [
            "Backup", "Backup Nextcloud", "Backup BookStack", "Backup Pangolin",
            'Wiki "BookStack" \\ prod', "Cron DNS",
        ])
        self.assertEqual(monitors[0], {"name": "Backup", "type": "group", "status": 0})

    def test_malformed_labels(self):
        with self.assertRaises(ValueError):
            kuma_summary.parse_labels('a="1",b')


class SummaryTest(unittest.TestCase):
    def setUp(self):
        self.monitors = kuma_summary.parse_monitors(METRICS)

    def test_down_lists_probes_not_folders(self):
        self.assertEqual(kuma_summary.summarize_down(self.monitors), {
            "items": [
                {"name": "Backup Nextcloud", "status": "En panne"},
                {"name": "Cron DNS", "status": "En panne"},
            ],
            "down": 2,
            "monitors": 5,
        })

    def test_nothing_down(self):
        summary = kuma_summary.summarize_down([{"name": "Wiki", "type": "http", "status": 1}])
        self.assertEqual(summary["items"], [{"name": "Toutes les sondes", "status": "en ligne (1)"}])
        self.assertEqual(summary["down"], 0)

    def test_backups_late_first(self):
        self.assertEqual(kuma_summary.summarize_backups(self.monitors, "Backup "), {
            "items": [
                {"name": "Nextcloud", "status": "En retard"},
                {"name": "Pangolin", "status": "En attente"},
                {"name": "BookStack", "status": "OK"},
            ],
            "late": 2,
        })

    def test_fetch_refuses_plain_http(self):
        with self.assertRaises(kuma_summary.FetchError):
            kuma_summary.fetch("http://a.invalid/metrics", "k")


class CacheTest(unittest.TestCase):
    def setUp(self):
        self.now = 0.0
        self.calls = 0
        self.fail = False

        def fetcher(url, key):
            self.calls += 1
            if self.fail:
                raise kuma_summary.FetchError("HTTP 401")
            return f'monitor_status{{monitor_name="M{self.calls}",monitor_type="http"}} 1\n'

        self.cache = kuma_summary.Cache("u", "k", 60, fetcher, lambda: self.now)

    def test_served_from_cache_within_ttl(self):
        self.assertEqual(self.cache.monitors()[0]["name"], "M1")
        self.now = 59
        self.assertEqual(self.cache.monitors()[0]["name"], "M1")
        self.now = 60
        self.assertEqual(self.cache.monitors()[0]["name"], "M2")

    def test_stale_copy_when_upstream_fails(self):
        self.cache.monitors()
        self.now, self.fail = 1000, True
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(self.cache.monitors()[0]["name"], "M1")

    def test_error_without_any_copy(self):
        self.fail = True
        with self.assertRaises(kuma_summary.FetchError):
            self.cache.monitors()


class ServerTest(unittest.TestCase):
    def start(self, fetcher):
        cache = kuma_summary.Cache("https://kuma.example.invalid/metrics", "secret-key", 60, fetcher)
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), kuma_summary.make_handler(cache, "Backup "))
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"
        self.silence = contextlib.redirect_stderr(io.StringIO())
        self.silence.__enter__()
        self.addCleanup(self.stop)

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.silence.__exit__(None, None, None)

    def get(self, path):
        try:
            with urllib.request.urlopen(self.base + path, timeout=5) as response:  # noqa: S310
                return response.status, response.read()
        except urllib.error.HTTPError as err:
            return err.code, err.read()

    def test_routes(self):
        self.start(lambda url, key: METRICS)
        status, body = self.get("/backups.json")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["late"], 2)
        status, body = self.get("/down.json")
        self.assertEqual((status, json.loads(body)["down"]), (200, 2))
        self.assertEqual(self.get("/healthz")[0], 200)
        self.assertEqual(self.get("/metrics")[0], 404)

    def test_upstream_error_hides_url_and_key(self):
        def fetcher(url, key):
            raise kuma_summary.FetchError("HTTP 401")

        self.start(fetcher)
        status, body = self.get("/down.json")
        self.assertEqual(status, 502)
        self.assertNotIn(b"secret-key", body)
        self.assertNotIn(b"kuma.example.invalid", body)


if __name__ == "__main__":
    unittest.main()
