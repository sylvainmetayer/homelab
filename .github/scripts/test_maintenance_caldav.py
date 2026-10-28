"""Tests of maintenance_caldav.py against a fake CalDAV server on 127.0.0.1
(Lint workflow: python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""

import base64
import datetime
import io
import threading
import unittest
import urllib.parse
from contextlib import redirect_stdout
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import maintenance_caldav as caldav

COLLECTION = "/remote.php/dav/calendars/sylvain/maintenance-homelab/"
USER = "sylvain"
GOOD = "fake-app-password-for-tests"
NOW = datetime.datetime(2026, 10, 28, 12, 0, tzinfo=datetime.timezone.utc)


class FakeCalDAV(BaseHTTPRequestHandler):
    """A calendar collection: PROPFIND (Depth 0/1), MKCALENDAR, PUT, DELETE, Basic auth."""

    state = None  # {"exists": bool, "objects": {name: text}, "log": [(method, name)], "redirect": bool}

    def log_message(self, *args):
        return

    def reply(self, status, body=b"", headers=None):
        self.send_response(status)
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def handle_any(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode() if length else ""
        path = urllib.parse.urlsplit(self.path).path
        name = urllib.parse.unquote(path[len(COLLECTION):]) if path.startswith(COLLECTION) else None
        st = self.state
        st["log"].append((self.command, name))
        expected = "Basic " + base64.b64encode(f"{USER}:{GOOD}".encode()).decode()
        if self.headers.get("Authorization") != expected:
            return self.reply(401)
        if st.get("redirect"):
            return self.reply(301, headers={"Location": "https://elsewhere.invalid/"})
        if name is None:
            return self.reply(404)
        if self.command == "PROPFIND":
            if not st["exists"]:
                return self.reply(404)
            hrefs = [COLLECTION] if self.headers.get("Depth") == "0" else [COLLECTION] + [
                COLLECTION + urllib.parse.quote(obj) for obj in st["objects"]
            ]
            xml = '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">' + "".join(
                f"<d:response><d:href>{href}</d:href></d:response>" for href in hrefs
            ) + "</d:multistatus>"
            return self.reply(207, xml.encode())
        if self.command == "MKCALENDAR":
            if st["exists"]:
                return self.reply(405)
            st["exists"] = True
            st["mkcalendar"] = body
            return self.reply(201)
        if not st["exists"]:
            return self.reply(404)
        if self.command == "PUT":
            created = name not in st["objects"]
            st["objects"][name] = body
            return self.reply(201 if created else 204)
        if self.command == "DELETE":
            return self.reply(204 if st["objects"].pop(name, None) is not None else 404)
        return self.reply(405)

    do_PROPFIND = do_MKCALENDAR = do_PUT = do_DELETE = handle_any


class CalDAVTest(unittest.TestCase):
    def setUp(self):
        self.state = {"exists": False, "objects": {}, "log": []}
        handler = type("Handler", (FakeCalDAV,), {"state": self.state})
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.url = f"http://127.0.0.1:{self.server.server_port}{COLLECTION}"

    def client(self, password=GOOD):
        return caldav.Client(self.url, USER, password)

    def objects(self, *uids):
        event = {"summary": "x", "description": "y", "date": datetime.date(2027, 1, 9)}
        return {uid: caldav.ics.render([dict(event, uid=uid)], NOW, feed=False) for uid in uids}

    def test_creates_the_calendar_then_upserts_without_duplicates(self):
        objects = self.objects("rotation-2027-01-09@homelab.sylvain.dev", "restore-test@homelab.sylvain.dev")
        self.assertEqual(caldav.sync(self.client(), objects), (True, 2, []))
        self.assertIn("<d:displayname>Maintenance homelab</d:displayname>", self.state["mkcalendar"])
        self.assertEqual(sorted(self.state["objects"]), ["restore-test@homelab.sylvain.dev.ics", "rotation-2027-01-09@homelab.sylvain.dev.ics"])
        self.assertEqual(caldav.sync(self.client(), objects), (False, 2, []))
        self.assertEqual(len(self.state["objects"]), 2)
        self.assertNotIn("METHOD:", self.state["objects"]["restore-test@homelab.sylvain.dev.ics"])

    def test_deletes_only_its_own_stale_events(self):
        self.state["exists"] = True
        self.state["objects"] = {
            "rotation-2027-01-09@homelab.sylvain.dev.ics": "old",
            "added-by-hand.ics": "keep",
            "other@example.org.ics": "keep",
        }
        created, written, stale = caldav.sync(self.client(), self.objects("restore-test@homelab.sylvain.dev"))
        self.assertEqual((created, written, stale), (False, 1, ["rotation-2027-01-09@homelab.sylvain.dev.ics"]))
        self.assertEqual(sorted(self.state["objects"]), ["added-by-hand.ics", "other@example.org.ics", "restore-test@homelab.sylvain.dev.ics"])
        self.assertEqual([method for method, _ in self.state["log"]].count("PROPFIND"), 1)

    def test_a_refused_password_never_shows_up_in_the_error(self):
        with self.assertRaises(caldav.CalDAVError) as raised:
            caldav.sync(self.client("wrong-password-value"), self.objects("a@homelab.sylvain.dev"))
        self.assertEqual(str(raised.exception), "PROPFIND <calendrier> : HTTP 401")
        self.assertNotIn("wrong-password-value", str(raised.exception))

    def test_redirects_are_not_followed(self):
        self.state["redirect"] = True
        with self.assertRaises(caldav.CalDAVError) as raised:
            caldav.sync(self.client(), self.objects("a@homelab.sylvain.dev"))
        self.assertIn("HTTP 301", str(raised.exception))

    def test_refuses_plain_http_off_loopback(self):
        with self.assertRaises(caldav.CalDAVError):
            caldav.Client("http://sylvain.cloud/remote.php/dav/calendars/sylvain/x/", USER, GOOD)

    def test_main_syncs_the_repository_calendar(self):
        environ = {"CALDAV_URL": self.url, "CALDAV_USER": USER, "CALDAV_PASSWORD": GOOD}
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(caldav.main([], environ=environ), 0)
        self.assertIn("Calendrier créé.", out.getvalue())
        self.assertNotIn(GOOD, out.getvalue())
        self.assertTrue(self.state["objects"])
        self.assertTrue(all(name.endswith(caldav.SUFFIX) for name in self.state["objects"]))

    def test_main_requires_the_credentials(self):
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(caldav.main([], environ={"CALDAV_URL": self.url}), 1)
        self.assertIn("CALDAV_USER, CALDAV_PASSWORD", out.getvalue())
        self.assertEqual(self.state["log"], [])

    def test_a_name_is_encoded_once_on_the_wire(self):
        self.state["exists"] = True
        client = self.client()
        client.put(caldav.object_name("a b@homelab.sylvain.dev"), "x")
        self.assertEqual(list(self.state["objects"]), ["a b@homelab.sylvain.dev.ics"])
        self.assertEqual(client.list_objects(), {"a b@homelab.sylvain.dev.ics"})
        client.delete("a b@homelab.sylvain.dev.ics")
        self.assertEqual(self.state["objects"], {})


class PlanTest(unittest.TestCase):
    def test_object_names_follow_the_uid(self):
        self.assertEqual(caldav.object_name("domains-todo@homelab.sylvain.dev"), "domains-todo@homelab.sylvain.dev.ics")
        self.assertEqual(caldav.object_name("a b@homelab.sylvain.dev"), "a b@homelab.sylvain.dev.ics")


if __name__ == "__main__":
    unittest.main()
