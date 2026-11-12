"""Tests de ansible/roles/dav_copy/files/dav_copy.py, sans réseau : deux faux serveurs DAV en mémoire."""
import base64
import hashlib
import http.server
import importlib.util
import os
import tempfile
import threading
import unittest
from argparse import Namespace
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "dav_copy", Path(__file__).resolve().parents[2] / "ansible/roles/dav_copy/files/dav_copy.py")
dc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dc)

NS = 'xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cr="urn:ietf:params:xml:ns:carddav"'


def ics(uid, extra=""):
    return f"BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//\r\nBEGIN:VEVENT\r\nUID:{uid}\r\nSUMMARY:s {uid}\r\n{extra}END:VEVENT\r\nEND:VCALENDAR\r\n"


class Fake:
    """Serveur DAV minimal : /dav/ (principal), /dav/calendars/u/ et /dav/addressbooks/u/ (collections)."""

    def __init__(self):
        self.colls = {}  # chemin -> {"kind", "name", "objs": {nom: texte}}
        self.log = []
        self.fail_puts = 0  # nombre de PUT à refuser en 404 (juste après MKCALENDAR)
        fake = self

        class H(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def send(self, code, body=b"", headers=None):
                self.send_response(code)
                for k, v in (headers or {}).items():
                    self.send_header(k, v)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def body(self):
                return self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode()

            def multistatus(self, items):
                rs = "".join(f"<d:response><d:href>{h}</d:href><d:propstat><d:prop>{p}</d:prop>"
                             "<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>" for h, p in items)
                self.send(207, f'<?xml version="1.0"?><d:multistatus {NS}>{rs}</d:multistatus>'.encode())

            def handle_one(self):
                m, path = self.command, self.path
                fake.log.append((m, path))
                parts = path.strip("/").split("/")
                if m == "PROPFIND":
                    self.body()
                    if path == "/dav/":
                        return self.multistatus([(path, "<d:current-user-principal><d:href>/dav/p/u/</d:href></d:current-user-principal>")])
                    if path == "/dav/p/u/":
                        return self.multistatus([(path, "<c:calendar-home-set><d:href>/dav/calendars/u/</d:href></c:calendar-home-set>"
                                                  "<cr:addressbook-home-set><d:href>/dav/addressbooks/u/</d:href></cr:addressbook-home-set>")])
                    if path.rstrip("/") in ("/dav/calendars/u", "/dav/addressbooks/u"):
                        items = []
                        for p, c in fake.colls.items():
                            if p.startswith(path.rstrip("/") + "/"):
                                rt = "<c:calendar/>" if c["kind"] == "calendar" else "<cr:addressbook/>"
                                if c.get("subscribed"):
                                    rt += '<x:subscribed xmlns:x="http://calendarserver.org/ns/"/>'
                                items.append((p, f"<d:resourcetype><d:collection/>{rt}</d:resourcetype>"
                                                 f"<d:displayname>{c['name']}</d:displayname>"
                                                 '<c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set>'))
                        return self.multistatus(items)
                    c = fake.colls.get(path)
                    if c is None:
                        return self.send(404)
                    items = [(path, "<d:resourcetype><d:collection/></d:resourcetype>")]
                    items += [(path + n, f"<d:getetag>{fake.etag(t)}</d:getetag>") for n, t in c["objs"].items()]
                    return self.multistatus(items)
                cpath = "/" + "/".join(parts[:-1]) + "/"
                c = fake.colls.get(cpath)
                if m == "MKCALENDAR":
                    self.body()
                    fake.colls[path] = {"kind": "calendar", "name": "n", "objs": {}, "fresh": True}
                    return self.send(201)
                if c is None:
                    return self.send(404)
                name = parts[-1]
                if m == "GET":
                    return self.send(200, c["objs"][name].encode()) if name in c["objs"] else self.send(404)
                if m == "PUT":
                    data = self.body()
                    if fake.fail_puts > 0:
                        fake.fail_puts -= 1
                        return self.send(404)
                    if self.headers.get("If-None-Match") == "*" and name in c["objs"]:
                        return self.send(412)
                    im = self.headers.get("If-Match")
                    if im and (name not in c["objs"] or fake.etag(c["objs"][name]) != im):
                        return self.send(412)
                    c["objs"][name] = data
                    return self.send(201, headers={"ETag": fake.etag(data)})
                if m == "DELETE":
                    c["objs"].pop(name, None)
                    return self.send(204)
                self.send(405)

            do_PROPFIND = do_GET = do_PUT = do_DELETE = do_MKCALENDAR = handle_one

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.server.server_port}/dav/"

    @staticmethod
    def etag(text):
        return '"' + hashlib.md5(text.encode()).hexdigest() + '"'

    def add(self, kind, slug, name, objs, **kw):
        home = "calendars" if kind == "calendar" else "addressbooks"
        self.colls[f"/dav/{home}/u/{slug}/"] = {"kind": kind, "name": name, "objs": dict(objs), **kw}

    def writes(self):
        return [e for e in self.log if e[0] not in dc.READ_METHODS]

    def close(self):
        self.server.shutdown()
        self.server.server_close()


def opts(**kw):
    return Namespace(**{"apply": False, "delete": False, "max_delete_pct": 10, "retries": 3, "retry_delay": 0, **kw})


class Base(unittest.TestCase):
    def setUp(self):
        self.s, self.d = Fake(), Fake()
        self.addCleanup(self.s.close)
        self.addCleanup(self.d.close)

    def go(self, cfg, state=None, **kw):
        o = opts(**kw)
        src = dc.Dav(self.s.url, "u", "x", read_only=True, allow_http=True)
        dst = dc.Dav(self.d.url, "u", "x", read_only=not o.apply, allow_http=True)
        return dc.run(src, dst, "u", "u", cfg, o, {} if state is None else state)

    CAL = {"calendars": [{"source": "a", "dest": "A"}]}


class Copy(Base):
    def setUp(self):
        super().setUp()
        self.s.add("calendar", "a", "Agenda", {f"{i}.ics": ics(f"u{i}") for i in range(10)})
        self.d.add("calendar", "a", "A", {})

    def test_dry_run_writes_nothing(self):
        (r,) = self.go(self.CAL)
        self.assertEqual((r["source"], r["created"], r["errors"]), (10, 10, []))
        self.assertEqual(self.d.writes(), [])
        self.assertEqual(self.s.writes(), [])
        self.assertEqual(self.d.colls["/dav/calendars/u/a/"]["objs"], {})

    def test_apply_then_rerun_is_idempotent(self):
        state = {}
        (r,) = self.go(self.CAL, state, apply=True)
        self.assertEqual((r["created"], r["errors"]), (10, []))
        self.d.log.clear()
        (r,) = self.go(self.CAL, state, apply=True)
        self.assertEqual((r["created"], r["modified"], r["unchanged"]), (0, 0, 10))
        self.assertEqual(self.d.writes(), [])
        self.assertEqual([e for e in self.s.log if e[0] == "GET"][10:], [])  # l'état évite de tout relire
        (r,) = self.go(self.CAL, {}, apply=True)  # sans état : comparaison du contenu, toujours 0 écriture
        self.assertEqual((r["modified"], r["unchanged"]), (0, 10))
        self.assertEqual(self.d.writes(), [])

    def test_modified_object_is_rewritten(self):
        state = {}
        self.go(self.CAL, state, apply=True)
        self.s.colls["/dav/calendars/u/a/"]["objs"]["3.ics"] = ics("u3", "DESCRIPTION:x\r\n")
        (r,) = self.go(self.CAL, state, apply=True)
        self.assertEqual((r["modified"], r["unchanged"]), (1, 9))

    def test_source_never_written(self):
        self.go(self.CAL, apply=True, delete=True)
        self.assertEqual(self.s.writes(), [])
        with self.assertRaises(dc.ReadOnlyError):
            dc.Dav(self.s.url, "u", "x", read_only=True, allow_http=True).request("PUT", "/dav/x", "d")
        for m in ("DELETE", "MKCALENDAR", "PROPPATCH", "POST"):
            with self.assertRaises(dc.ReadOnlyError):
                dc.Dav(self.s.url, "u", "x", read_only=True, allow_http=True).request(m, "/dav/x")

    def test_missing_calendar_created_after_retries(self):
        self.d.colls.clear()
        self.d.fail_puts = 2  # l'écriture juste après MKCALENDAR échoue d'abord
        (r,) = self.go(self.CAL, apply=True)
        self.assertEqual((r["created"], r["errors"]), (10, []))
        self.assertEqual(len(self.d.colls["/dav/calendars/u/a/"]["objs"]), 10)

    def test_missing_calendar_dry_run(self):
        self.d.colls.clear()
        (r,) = self.go(self.CAL)
        self.assertEqual(r["created"], 10)
        self.assertEqual(self.d.writes(), [])


class Deletions(Base):
    def fill(self, n_dest_extra):
        self.s.add("calendar", "a", "Agenda", {f"{i}.ics": ics(f"u{i}") for i in range(20)})
        objs = {f"{i}.ics": ics(f"u{i}") for i in range(20)}
        objs.update({f"gone{i}.ics": ics(f"g{i}") for i in range(n_dest_extra)})
        self.d.add("calendar", "a", "A", objs)

    def test_listed_but_not_deleted_without_flag(self):
        self.fill(1)
        (r,) = self.go(self.CAL, apply=True)
        self.assertEqual((r["to_delete"], r["deleted"], r["errors"]), (1, 0, []))
        self.assertIn("gone0.ics", self.d.colls["/dav/calendars/u/a/"]["objs"])

    def test_deleted_with_flag(self):
        self.fill(1)
        (r,) = self.go(self.CAL, apply=True, delete=True)
        self.assertEqual((r["deleted"], r["errors"]), (1, []))
        self.assertNotIn("gone0.ics", self.d.colls["/dav/calendars/u/a/"]["objs"])

    def test_guard_skips_collection(self):
        self.fill(5)  # 5 sur 25 = 20 % > 10 %
        (r,) = self.go(self.CAL, apply=True, delete=True)
        self.assertEqual(len(r["errors"]), 1)
        self.assertIn("garde-fou", r["errors"][0])
        self.assertEqual(self.d.writes(), [])
        self.assertEqual(len(self.d.colls["/dav/calendars/u/a/"]["objs"]), 25)


class AddressBooks(Base):
    def test_missing_book_is_an_error_and_others_continue(self):
        self.s.add("addressbook", "c", "Contacts", {"1.vcf": "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:A\r\nEND:VCARD\r\n"})
        self.s.add("calendar", "a", "Agenda", {"1.ics": ics("u1")})
        self.d.add("calendar", "a", "A", {})
        cfg = {"calendars": [{"source": "a", "dest": "A"}], "addressbooks": [{"source": "c", "dest": "Contacts"}]}
        rs = self.go(cfg, apply=True)
        self.assertEqual(rs[0]["created"], 1)
        self.assertEqual(len(rs[1]["errors"]), 1)
        self.assertEqual(self.d.writes()[0][0], "PUT")
        self.assertFalse([e for e in self.d.writes() if e[0] == "MKCALENDAR"])

    def test_vcard4_equals_vcard3(self):
        photo = base64.b64encode(b"\x89PNG-bytes").decode()
        v4 = ("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Jean Dupont\r\nTEL;VALUE=uri;TYPE=home,voice;PREF=1:tel:+33123\r\n"
              f"BDAY:--0412\r\nPHOTO:data:image/png;base64,{photo}\r\nitem1.EMAIL;TYPE=work:a@b.fr\r\nEND:VCARD\r\n")
        v3 = ("BEGIN:VCARD\r\nVERSION:3.0\r\nPRODID:-//x\r\nEMAIL;type=WORK:a@b.fr\r\nBDAY:1604-04-12\r\n"
              f"TEL;TYPE=HOME,VOICE,PREF:+33123\r\nPHOTO;ENCODING=b;TYPE=PNG:{photo[:20]}\r\n {photo[20:]}\r\nFN:Jean Dupont\r\nEND:VCARD\r\n")
        self.assertEqual(dc.normalize(v4, True), dc.normalize(v3, True))
        self.assertNotEqual(dc.normalize(v4, True), dc.normalize(v3.replace("Dupont", "Durand"), True))
        self.assertNotEqual(dc.normalize(v4, True), dc.normalize(v3.replace("1604-04-12", "1990-04-12"), True))


class ScheduleAgent(unittest.TestCase):
    def agents(self, text):
        return [(n, ps.get("SCHEDULE-AGENT")) for l, _ in dc.logical_lines(text) for n, ps, _v in [dc.parse_prop(l)]
                if n in ("ORGANIZER", "ATTENDEE")]

    def test_added_everywhere_including_folded_and_existing(self):
        long_cn = "x" * 90
        text = ics("u", (f"ORGANIZER;CN=Moi:mailto:o@x.fr\r\nATTENDEE;CN={long_cn};ROLE=REQ-PARTICIPANT:\r\n :mailto:a@x.fr\r\n"
                         "ATTENDEE;SCHEDULE-AGENT=SERVER;PARTSTAT=ACCEPTED:mailto:b@x.fr\r\n"
                         'ATTENDEE;CN="a;b:c";schedule-agent=NONE:mailto:c@x.fr\r\n'))
        out = dc.add_schedule_agent(text)
        self.assertEqual(self.agents(out), [("ORGANIZER", ["CLIENT"]), ("ATTENDEE", ["CLIENT"]),
                                            ("ATTENDEE", ["CLIENT"]), ("ATTENDEE", ["CLIENT"])])
        self.assertEqual(out.count("SCHEDULE-AGENT"), 4)  # un seul paramètre par ligne, l'ancien est remplacé
        self.assertTrue(all(len(l) <= 75 for l in out.split("\r\n")))
        self.assertIn("mailto:a@x.fr", "".join(l.lstrip(" ") for l in out.split("\r\n")))
        self.assertEqual(dc.add_schedule_agent(out), out)  # idempotent
        self.assertIn('CN="a;b:c"', out)

    def test_untouched_outside_event_and_todo(self):
        text = ics("u").replace("END:VEVENT", "END:VEVENT\r\nBEGIN:VJOURNAL\r\nORGANIZER:mailto:o@x.fr\r\nEND:VJOURNAL")
        self.assertNotIn("SCHEDULE-AGENT", dc.add_schedule_agent(text))

    def test_applied_on_copy(self):
        s, d = Fake(), Fake()
        self.addCleanup(s.close)
        self.addCleanup(d.close)
        s.add("calendar", "a", "A", {"1.ics": ics("u1", "ORGANIZER:mailto:o@x.fr\r\nATTENDEE:mailto:a@x.fr\r\n")})
        d.add("calendar", "a", "A", {})
        dc.run(dc.Dav(s.url, "u", "x", True, True), dc.Dav(d.url, "u", "x", False, True), "u", "u",
               {"calendars": [{"source": "a", "dest": "A"}]}, opts(apply=True), {})
        self.assertEqual(d.colls["/dav/calendars/u/a/"]["objs"]["1.ics"].count("SCHEDULE-AGENT=CLIENT"), 2)


class Config(unittest.TestCase):
    def test_https_only(self):
        with self.assertRaises(ValueError):
            dc.Dav("http://example.invalid/dav/", "u", "x", True)

    def test_both_separators_and_user_from_url(self):
        with tempfile.TemporaryDirectory() as t:
            p = os.path.join(t, "c")
            Path(p).write_text("USER : bob\nMDP=pw\n")
            self.assertEqual(dc.load_conf(p, "https://h/dav/"), ("https://h/dav/", "bob", "pw"))
            Path(p).write_text("URL: https://h/calendars/SM1/abc\n\nMDP: pw\n")
            self.assertEqual(dc.load_conf(p), ("https://h/calendars/SM1/abc", "SM1", "pw"))


if __name__ == "__main__":
    unittest.main()
