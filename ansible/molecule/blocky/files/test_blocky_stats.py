"""Tests de blocky_stats.py (rôle blocky), lancés par verify.yml du scénario
blocky avec le python3 de l'hôte de test. À la main : copier ce fichier à côté
de ansible/roles/blocky/files/blocky_stats.py, puis
python3 -I -m unittest discover -s . -p 'test_*.py'.
"""

import http.server
import io
import json
import os
import tempfile
import threading
import unittest
from contextlib import redirect_stderr, redirect_stdout

import blocky_stats

METRICS = """\
# HELP blocky_query_total Number of total queries
# TYPE blocky_query_total counter
blocky_query_total{client="192.168.1.10",type="A"} 1.234567e+06
blocky_query_total{client="192.168.1.11",type="AAAA"} 33
# TYPE blocky_response_total counter
blocky_response_total{reason="BLOCKED (ads)",response_code="NOERROR",response_type="BLOCKED"} 100
blocky_response_total{reason="BLOCKED (threats)",response_code="NOERROR",response_type="BLOCKED"} 5
blocky_response_total{reason="CACHED",response_code="NOERROR",response_type="CACHED"} 900
blocky_response_total{reason="RESOLVED",response_code="NOERROR",response_type="RESOLVED"} 400
blocky_blocking_enabled 1
blocky_query_total_bogus 999
process_start_time_seconds 1.76e+09
"""


class ParseTest(unittest.TestCase):
    def test_sums_every_label_set(self):
        queries, blocked, start = blocky_stats.parse(METRICS)
        self.assertEqual(queries, 1234600)
        self.assertEqual(blocked, 105)
        self.assertEqual(start, 1.76e9)

    def test_empty_metrics(self):
        self.assertEqual(blocky_stats.parse(""), (0.0, 0.0, None))

    def test_ignores_garbage(self):
        text = "blocky_query_total{a=\"b\"} NaN\nblocky_query_total oops\nblocky_query_total\n"
        self.assertEqual(blocky_stats.parse(text), (0.0, 0.0, None))


class ComputeTest(unittest.TestCase):
    def test_first_run_counts_nothing(self):
        line, state = blocky_stats.compute((50.0, 5.0, 10.0), {})
        self.assertEqual(line, "event=blocky_stats queries=0 blocked=0 queries_total=50 blocked_total=5")
        self.assertEqual(state, {"queries": 50.0, "blocked": 5.0, "start": 10.0})

    def test_delta_since_previous(self):
        line, _ = blocky_stats.compute((80.0, 9.0, 10.0), {"queries": 50.0, "blocked": 5.0, "start": 10.0})
        self.assertIn("queries=30 blocked=4 ", line)

    def test_restart_by_start_time_counts_since_restart(self):
        # Le compteur est remonté plus haut qu'avant : seule l'heure de
        # démarrage dit qu'il est reparti de zéro.
        line, _ = blocky_stats.compute((70.0, 6.0, 20.0), {"queries": 50.0, "blocked": 5.0, "start": 10.0})
        self.assertIn("queries=70 blocked=6 ", line)

    def test_restart_by_lower_counter(self):
        line, _ = blocky_stats.compute((12.0, 1.0, None), {"queries": 50.0, "blocked": 5.0, "start": None})
        self.assertIn("queries=12 blocked=1 ", line)

    def test_large_values_are_integers(self):
        line, _ = blocky_stats.compute((1234600.0, 105.0, None), {"queries": 1234500.0, "blocked": 100.0})
        self.assertIn("queries=100 blocked=5 queries_total=1234600 blocked_total=105", line)


class _Handler(http.server.BaseHTTPRequestHandler):
    body = METRICS.encode()

    def do_GET(self):  # noqa: N802
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(self.body)

    def log_message(self, *args):
        pass


class MainTest(unittest.TestCase):
    def start_server(self):
        self.server = http.server.HTTPServer(("127.0.0.1", 0), _Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def setUp(self):
        self.start_server()
        self.url = f"http://127.0.0.1:{self.server.server_port}/metrics"
        self.dir = tempfile.TemporaryDirectory()
        os.environ["STATE_DIRECTORY"] = self.dir.name

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.dir.cleanup()
        os.environ.pop("STATE_DIRECTORY", None)

    def run_main(self, url=None):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = blocky_stats.main(["blocky_stats.py", url or self.url])
        return code, out.getvalue(), err.getvalue()

    def test_two_runs_keep_state(self):
        code, out, _ = self.run_main()
        self.assertEqual(code, 0)
        self.assertEqual(out, "event=blocky_stats queries=0 blocked=0 queries_total=1234600 blocked_total=105\n")
        with open(os.path.join(self.dir.name, "counters.json"), encoding="utf-8") as handle:
            self.assertEqual(json.load(handle)["queries"], 1234600)
        code, out, _ = self.run_main()
        self.assertEqual(out, "event=blocky_stats queries=0 blocked=0 queries_total=1234600 blocked_total=105\n")

    def test_unreachable_never_fails_nor_logs_a_line(self):
        port = self.server.server_port
        self.server.shutdown()
        self.server.server_close()
        code, out, err = self.run_main(f"http://127.0.0.1:{port}/metrics")
        self.assertEqual(code, 0)
        self.assertEqual(out, "")
        self.assertIn("métriques illisibles", err)
        self.assertFalse(os.path.exists(os.path.join(self.dir.name, "counters.json")))
        # Pour le tearDown.
        self.start_server()

    def test_corrupt_state_counts_as_first_run(self):
        with open(os.path.join(self.dir.name, "counters.json"), "w", encoding="utf-8") as handle:
            handle.write("{not json")
        _, out, _ = self.run_main()
        self.assertIn("queries=0 blocked=0 ", out)

    def test_missing_state_directory(self):
        os.environ.pop("STATE_DIRECTORY")
        code, out, err = self.run_main()
        self.assertEqual((code, out), (0, ""))
        self.assertIn("STATE_DIRECTORY", err)


if __name__ == "__main__":
    unittest.main()
