"""Tests de apps_summary.py (rôle homepage), lancés par verify.yml.

Usage : python3 -I -m unittest discover -s <dossier> -p 'test_*.py', le
dossier contenant ce fichier et apps_summary.py.
"""

import contextlib
import io
import json
import os
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request
from http.server import ThreadingHTTPServer
from unittest import mock

import apps_summary

# 2026-11-01 14:00:00 UTC, 15:00 à Paris (heure d'hiver).
NOW = 1793541600.0
PARIS = "CET-1CEST,M3.5.0,M10.5.0/3"


def paris(test):
    """Lance test à l'heure de Paris (Grocy et Dawarich lisent l'heure locale)."""

    def wrapper(self):
        try:
            with mock.patch.dict(os.environ, {"TZ": PARIS}):
                time.tzset()
                test(self)
        finally:
            time.tzset()

    return wrapper


class GrocyTest(unittest.TestCase):
    @paris
    def test_counts_and_overdue_chores_in_local_time(self):
        raw = {
            "volatile": {
                "due_products": [{}, {}],
                "overdue_products": [{}],
                "expired_products": [{}, {}],
                "missing_products": [{}],
            },
            "chores": [
                {"next_estimated_execution_time": "2026-11-01 14:59:00"},  # passée à 15:00 locale
                {"next_estimated_execution_time": "2026-11-01 15:30:00"},  # pas encore
                {"next_estimated_execution_time": None},  # manuelle, sans échéance
                "illisible",
            ],
        }
        self.assertEqual(apps_summary.summarize_grocy(raw, NOW),
                         {"due_soon": 2, "overdue": 3, "missing": 1, "chores_overdue": 1})

    def test_missing_fields_count_zero(self):
        self.assertEqual(apps_summary.summarize_grocy({}, NOW),
                         {"due_soon": 0, "overdue": 0, "missing": 0, "chores_overdue": 0})

    def test_fetch_sends_the_key_header(self):
        calls = []

        def fake(url, headers, https_only=False):
            calls.append((url, headers))
            return {}

        with mock.patch.object(apps_summary, "fetch_json", fake):
            apps_summary.fetch_grocy({"GROCY_URL": "http://grocy:80/", "GROCY_API_KEY": "k", "GROCY_DUE_SOON_DAYS": "3"})
        self.assertEqual([url for url, _ in calls],
                         ["http://grocy:80/api/stock/volatile?due_soon_days=3", "http://grocy:80/api/chores"])
        self.assertEqual(calls[0][1]["GROCY-API-KEY"], "k")


class PapraTest(unittest.TestCase):
    def test_recent_query_is_a_date_seven_days_back(self):
        self.assertEqual(apps_summary.papra_recent_query(NOW), "created:>2026-10-25")

    def test_sums_every_organization(self):
        def fake(url, headers, https_only=False):
            self.assertEqual(headers["Authorization"], "Bearer ppapi_x")
            parsed = urllib.parse.urlsplit(url)
            if parsed.path == "/api/organizations":
                return {"organizations": [{"id": "org_a"}, {"id": "org_b"}]}
            if parsed.path.endswith("/documents/statistics"):
                return {"organizationStats": {"documentsCount": 10}}
            query = urllib.parse.parse_qs(parsed.query)
            self.assertEqual(query["pageSize"], ["1"])
            return {"documentsCount": 2 if query["searchQuery"] == ["-has:tags"] else 1}

        with mock.patch.object(apps_summary, "fetch_json", fake):
            raw = apps_summary.fetch_papra({"PAPRA_URL": "http://papra:1221", "PAPRA_API_KEY": "ppapi_x"}, NOW)
        self.assertEqual(apps_summary.summarize_papra(raw, NOW), {"documents": 20, "recent": 2, "untagged": 4})


class DawarichTest(unittest.TestCase):
    STATS = {
        "yearlyStats": [
            {"year": 2026, "totalDistanceKm": 1234, "totalCountriesVisited": 3,
             "monthlyDistanceKm": {"october": 300, "november": 42}},
            {"year": 2025, "totalDistanceKm": 9999, "totalCountriesVisited": 9, "monthlyDistanceKm": {}},
        ]
    }

    @paris
    def test_current_month_and_year(self):
        self.assertEqual(apps_summary.summarize_dawarich(self.STATS, NOW),
                         {"month_km": 42, "year_km": 1234, "year_countries": 3})

    def test_no_stats_for_the_year(self):
        self.assertEqual(apps_summary.summarize_dawarich({"yearlyStats": []}, NOW),
                         {"month_km": 0, "year_km": 0, "year_countries": 0})

    def test_public_host_header(self):
        seen = {}

        def fake(url, headers, https_only=False):
            seen.update(url=url, headers=headers)
            return {}

        with mock.patch.object(apps_summary, "fetch_json", fake):
            apps_summary.fetch_dawarich({"DAWARICH_URL": "http://dawarich-app:3000", "DAWARICH_API_KEY": "k",
                                         "DAWARICH_HOST": "tracks.example.invalid"})
        self.assertEqual(seen["url"], "http://dawarich-app:3000/api/v1/stats")
        self.assertEqual(seen["headers"]["Host"], "tracks.example.invalid")
        self.assertEqual(seen["headers"]["Authorization"], "Bearer k")


def visit(destination, when):
    return {"MonitoredVehicleJourney": {"DestinationName": [{"value": destination}],
                                        "MonitoredCall": {"ExpectedDepartureTime": when}}}


class TbmTest(unittest.TestCase):
    PAYLOAD = {"Siri": {"ServiceDelivery": {"StopMonitoringDelivery": [{"MonitoredStopVisit": [
        visit("CENON GARE", "2026-11-01T14:20:00Z"),
        visit("AMBARES CENTRE", "2026-11-01T14:05:00Z"),
        visit("GARE SAINT JEAN", "2026-11-01T13:50:00Z"),  # déjà passé
        visit("GARE SAINT JEAN", "pas une date"),
    ]}]}}}

    def test_parse_departures(self):
        departures = apps_summary.parse_departures(self.PAYLOAD)
        self.assertEqual(len(departures), 3)
        self.assertIn((NOW + 1200, "Cenon Gare"), departures)

    @paris
    def test_next_departures_per_stop(self):
        stops = [apps_summary.parse_departures(self.PAYLOAD), [(NOW + 20, "BEAUSOLEIL".title())]]
        summary = apps_summary.summarize_tbm({"stops": stops}, NOW, per_stop=1)
        self.assertEqual(summary["items"], [
            {"name": "Ambares Centre", "status": "5 min (15:05)"},
            {"name": "Beausoleil", "status": "à l'approche (15:00)"},
        ])

    def test_nothing_planned(self):
        self.assertEqual(apps_summary.summarize_tbm({"stops": [[]]}, NOW)["items"],
                         [{"name": "Aucun passage prévu", "status": ""}])

    def test_fetch_is_https_only(self):
        with self.assertRaises(apps_summary.FetchError):
            apps_summary.fetch_tbm({"TBM_URL": "http://tbm.invalid/sm.json", "TBM_STOPS": "a"})

    def test_internal_sources_refuse_other_schemes(self):
        with self.assertRaises(apps_summary.FetchError):
            apps_summary.fetch_json("file:///etc/passwd", {})


class NoRedirectTest(unittest.TestCase):
    def test_redirect_is_not_followed(self):
        request = urllib.request.Request("http://papra:1221/api/organizations", headers={"Authorization": "Bearer x"})
        self.assertIsNone(apps_summary._NoRedirect().redirect_request(request, None, 302, "Found", {}, "http://b/"))


class SourceTest(unittest.TestCase):
    def setUp(self):
        self.now = 0.0
        self.calls = 0
        self.fail = False

        def fetcher():
            self.calls += 1
            if self.fail:
                raise apps_summary.FetchError("HTTP 401")
            return {"n": self.calls}

        self.source = apps_summary.Source("test", fetcher, lambda raw, now: {"n": raw["n"], "now": now}, 60,
                                          lambda: self.now)

    def test_cached_within_ttl_and_summarized_at_request_time(self):
        self.assertEqual(self.source.summary(), {"n": 1, "now": 0.0})
        self.now = 59
        self.assertEqual(self.source.summary(), {"n": 1, "now": 59})
        self.now = 60
        self.assertEqual(self.source.summary()["n"], 2)

    def test_stale_copy_when_upstream_fails(self):
        self.source.summary()
        self.now, self.fail = 1000, True
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(self.source.summary()["n"], 1)

    def test_error_without_any_copy(self):
        self.fail = True
        with self.assertRaises(apps_summary.FetchError):
            self.source.summary()

    def test_unexpected_shape_is_a_fetch_error(self):
        source = apps_summary.Source("test", lambda: {}["absent"], lambda raw, now: raw, 60)
        with self.assertRaises(apps_summary.FetchError):
            source.summary()


    def test_unexpected_shape_at_summary_is_a_fetch_error(self):
        source = apps_summary.Source("test", lambda: {"yearlyStats": "pas une liste"},
                                     lambda raw, now: raw["absent"], 60)
        with self.assertRaises(apps_summary.FetchError):
            source.summary()


class CostsTest(unittest.TestCase):
    """Le costs.json du rôle cost_report, lu sur le disque."""

    def test_reads_the_file_and_keeps_the_card_fields(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "costs.json")
            with open(path, "w", encoding="utf-8") as handle:
                json.dump({"previous_label": "octobre 2026", "previous_total": "30,32 €", "current_total": "0,70 €",
                           "missing": 2, "incomplete": "PikaPods (à renseigner)", "updated": "01/11 07:00"}, handle)
            raw = apps_summary.fetch_costs({"COSTS_FILE": path})
        self.assertEqual(apps_summary.summarize_costs(raw, 0), {
            "previous_total": "30,32 €", "current_total": "0,70 €", "missing": 2, "updated": "01/11 07:00",
        })

    def test_missing_file_is_a_fetch_error(self):
        with self.assertRaises(apps_summary.FetchError):
            apps_summary.fetch_costs({"COSTS_FILE": "/nonexistent/costs.json"})


class BuildSourcesTest(unittest.TestCase):
    def test_only_sources_with_their_key(self):
        sources = apps_summary.build_sources({
            "GROCY_URL": "http://grocy:80", "GROCY_API_KEY": "",
            "PAPRA_URL": "http://papra:1221", "PAPRA_API_KEY": "k",
            "TBM_URL": "https://tbm.invalid/sm.json", "TBM_STOPS": "a,b",
            "COSTS_FILE": "/data/costs/costs.json",
        })
        self.assertEqual(sorted(sources), ["/costs.json", "/papra.json", "/tbm.json"])


class ServerTest(unittest.TestCase):
    def start(self, sources):
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), apps_summary.make_handler(sources))
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
        source = apps_summary.Source("papra", lambda: {"documents": 3}, apps_summary.summarize_papra, 60)
        self.start({"/papra.json": source})
        status, body = self.get("/papra.json")
        self.assertEqual((status, json.loads(body)), (200, {"documents": 3, "recent": 0, "untagged": 0}))
        self.assertEqual(self.get("/healthz")[0], 200)
        self.assertEqual(self.get("/grocy.json")[0], 404)

    def test_upstream_error_hides_url_and_key(self):
        def fetcher():
            raise apps_summary.FetchError("HTTP 401")

        self.start({"/grocy.json": apps_summary.Source("grocy", fetcher, apps_summary.summarize_grocy, 60)})
        status, body = self.get("/grocy.json")
        self.assertEqual(status, 502)
        self.assertNotIn(b"grocy:80", body)


if __name__ == "__main__":
    unittest.main()
