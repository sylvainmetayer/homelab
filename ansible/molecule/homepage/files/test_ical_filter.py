"""Tests de ical_filter.py (rôle homepage), lancés par verify.yml.

Usage : python3 -I -m unittest discover -s <dossier> -p 'test_*.py', le
dossier contenant ce fichier et ical_filter.py.
"""

import contextlib
import io
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

import ical_filter

# CRLF, lignes repliées (espace et tabulation), un VTODO à VALARM, un
# VJOURNAL, un VTODO en minuscules, et un VEVENT dont la description repliée
# contient « BEGIN:VTODO » en continuation : il reste.
CALENDAR = (
    b"BEGIN:VCALENDAR\r\n"
    b"VERSION:2.0\r\n"
    b"PRODID:-//Nextcloud//Calendar//FR\r\n"
    b"X-WR-CALNAME:Top nous\r\n"
    b"BEGIN:VTIMEZONE\r\n"
    b"TZID:Europe/Paris\r\n"
    b"BEGIN:STANDARD\r\n"
    b"TZOFFSETFROM:+0200\r\n"
    b"TZOFFSETTO:+0100\r\n"
    b"DTSTART:19701025T030000\r\n"
    b"END:STANDARD\r\n"
    b"END:VTIMEZONE\r\n"
    b"BEGIN:VTODO\r\n"
    b"UID:todo-1\r\n"
    b"SUMMARY:Acheter du pain avec un titre assez long pour \xc3\xaatre\r\n"
    b"  repli\xc3\xa9\r\n"
    b"BEGIN:VALARM\r\n"
    b"ACTION:DISPLAY\r\n"
    b"END:VALARM\r\n"
    b"END:VTODO\r\n"
    b"BEGIN:VEVENT\r\n"
    b"UID:event-1\r\n"
    b"DTSTART;TZID=Europe/Paris:20261105T190000\r\n"
    b"SUMMARY:D\xc3\xaener\r\n"
    b"DESCRIPTION:une description repli\xc3\xa9e qui cite\r\n"
    b" BEGIN:VTODO sans en \xc3\xaatre un\r\n"
    b"\tEND:VTODO non plus\r\n"
    b"END:VEVENT\r\n"
    b"BEGIN:VJOURNAL\r\n"
    b"UID:journal-1\r\n"
    b"END:VJOURNAL\r\n"
    b"begin:vtodo\r\n"
    b"UID:todo-2\r\n"
    b"end:vtodo\r\n"
    b"END:VCALENDAR\r\n"
)

EXPECTED = (
    b"BEGIN:VCALENDAR\r\n"
    b"VERSION:2.0\r\n"
    b"PRODID:-//Nextcloud//Calendar//FR\r\n"
    b"X-WR-CALNAME:Top nous\r\n"
    b"BEGIN:VTIMEZONE\r\n"
    b"TZID:Europe/Paris\r\n"
    b"BEGIN:STANDARD\r\n"
    b"TZOFFSETFROM:+0200\r\n"
    b"TZOFFSETTO:+0100\r\n"
    b"DTSTART:19701025T030000\r\n"
    b"END:STANDARD\r\n"
    b"END:VTIMEZONE\r\n"
    b"BEGIN:VEVENT\r\n"
    b"UID:event-1\r\n"
    b"DTSTART;TZID=Europe/Paris:20261105T190000\r\n"
    b"SUMMARY:D\xc3\xaener\r\n"
    b"DESCRIPTION:une description repli\xc3\xa9e qui cite\r\n"
    b" BEGIN:VTODO sans en \xc3\xaatre un\r\n"
    b"\tEND:VTODO non plus\r\n"
    b"END:VEVENT\r\n"
    b"END:VCALENDAR\r\n"
)


class FilterTest(unittest.TestCase):
    def test_drops_todos_and_journals_keeps_the_rest_verbatim(self):
        self.assertEqual(ical_filter.filter_calendar(CALENDAR), EXPECTED)

    def test_lf_line_endings_are_kept(self):
        lf = CALENDAR.replace(b"\r\n", b"\n")
        self.assertEqual(ical_filter.filter_calendar(lf), EXPECTED.replace(b"\r\n", b"\n"))

    def test_calendar_without_todo_is_unchanged(self):
        self.assertEqual(ical_filter.filter_calendar(EXPECTED), EXPECTED)


class FeedsTest(unittest.TestCase):
    def test_slug_from_variable_name(self):
        environ = {
            "ICAL_FEED_PERSO": "https://a.invalid/p",
            "ICAL_FEED_TOP_NOUS": "https://a.invalid/t",
            "ICAL_FEED_VIDE": "",
            "PATH": "/usr/bin",
        }
        self.assertEqual(
            ical_filter.feeds_from_env(environ),
            {"perso": "https://a.invalid/p", "top-nous": "https://a.invalid/t"},
        )

    def test_fetch_refuses_plain_http(self):
        with self.assertRaises(ical_filter.FeedError):
            ical_filter.fetch("http://a.invalid/p")


class CacheTest(unittest.TestCase):
    def setUp(self):
        self.now = 0.0
        self.calls = 0
        self.fail = False

        def fetcher(url):
            self.calls += 1
            if self.fail:
                raise ical_filter.FeedError("HTTP 503")
            return url.encode() + str(self.calls).encode()

        self.cache = ical_filter.Cache({"perso": "u"}, 300, fetcher, lambda: self.now)

    def test_served_from_cache_within_ttl(self):
        self.assertEqual(self.cache.get("perso"), b"u1")
        self.now = 299
        self.assertEqual(self.cache.get("perso"), b"u1")
        self.now = 300
        self.assertEqual(self.cache.get("perso"), b"u2")

    def test_stale_copy_when_upstream_fails(self):
        self.cache.get("perso")
        self.now, self.fail = 1000, True
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(self.cache.get("perso"), b"u1")

    def test_error_without_any_copy(self):
        self.fail = True
        with self.assertRaises(ical_filter.FeedError):
            self.cache.get("perso")


class ServerTest(unittest.TestCase):
    def setUp(self):
        def fetcher(url):
            if url == "broken":
                raise ical_filter.FeedError("HTTP 404")
            return EXPECTED

        cache = ical_filter.Cache({"top-nous": "ok", "perso": "broken"}, 300, fetcher)
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), ical_filter.make_handler(cache))
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"
        self.silence = contextlib.redirect_stderr(io.StringIO())
        self.silence.__enter__()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.silence.__exit__(None, None, None)

    def get(self, path):
        try:
            with urllib.request.urlopen(self.base + path, timeout=5) as response:  # noqa: S310
                return response.status, response.headers["Content-Type"], response.read()
        except urllib.error.HTTPError as err:
            return err.code, err.headers["Content-Type"], err.read()

    def test_feed(self):
        self.assertEqual(self.get("/top-nous.ics"), (200, "text/calendar; charset=utf-8", EXPECTED))

    def test_health(self):
        self.assertEqual(self.get("/healthz")[0], 200)

    def test_unknown_feed(self):
        self.assertEqual(self.get("/autre.ics")[0], 404)
        self.assertEqual(self.get("/top-nous")[0], 404)

    def test_upstream_error(self):
        status, _, body = self.get("/perso.ics")
        self.assertEqual(status, 502)
        self.assertNotIn(b"broken", body)


if __name__ == "__main__":
    unittest.main()
