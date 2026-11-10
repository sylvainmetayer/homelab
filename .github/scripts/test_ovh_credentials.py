"""Tests of ovh_credentials.py against a fake OVH API on 127.0.0.1, sops mocked
(Lint workflow: python -I -m unittest discover -s .github/scripts -p 'test_*.py')."""

import contextlib
import io
import json
import re
import subprocess
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import ovh_credentials as oc

AK, AS, CK, NEW_CK = "ak-fake-0001", "as-secret-fake-0002", "ck-current-fake-0003", "ck-new-fake-0004"
ENV = {"OVH_APPLICATION_KEY": AK, "OVH_APPLICATION_SECRET": AS, "OVH_CONSUMER_KEY": CK,
       "OVH_CLOUD_PROJECT_ID": "proj123", "home_ip": "203.0.113.7"}
SECRETS = (AS, CK, NEW_CK)
CURRENT, OLD, OTHER = 222, 111, 333  # OTHER: credential of another application (e.g. DNS-01 of the NAS)
APPS = {CURRENT: 7, OLD: 7, OTHER: 9}
VALIDATION = "https://www.ovh.com/auth/sso/api?credentialToken=tok"


class FakeOvh(BaseHTTPRequestHandler):
    """The /auth and /me/api routes the script calls; records every request."""

    # requests: every request received; fail: (code, body) returned to all. Set by Base.setUp.

    def log_message(self, *args):
        pass

    def _reply(self, code, payload):
        data = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _handle(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode()
        FakeOvh.requests.append((self.command, self.path, dict(self.headers), body))
        if FakeOvh.fail:
            return self._reply(*FakeOvh.fail)
        path = self.path.removeprefix("/1.0")
        if self.command == "POST" and path == "/auth/credential":
            return self._reply(200, {"consumerKey": NEW_CK, "state": "pendingValidation", "validationUrl": VALIDATION})
        if self.headers.get("X-Ovh-Consumer") != CK:
            return self._reply(403, {"errorCode": "INVALID_CREDENTIAL", "message": "bad"})
        if path == "/auth/currentCredential":
            return self._reply(200, {"credentialId": CURRENT, "applicationId": 7})
        if path == "/me/api/credential":
            return self._reply(200, [CURRENT, OTHER, OLD])
        app = re.fullmatch(r"/me/api/credential/(\d+)/application", path)
        if app:
            app_id = APPS[int(app[1])]
            return self._reply(200, {"applicationId": app_id, "applicationKey": AK, "name": f"app-{app_id}",
                                     "description": "nas-proxy DNS-01" if app_id == 9 else "tofu", "status": "active"})
        match = re.fullmatch(r"/me/api/credential/(\d+)", path)
        if match and self.command == "GET":
            return self._reply(200, {"credentialId": int(match[1]), "applicationId": APPS[int(match[1])], "status": "validated",
                                     "creation": "2025-11-01T10:00:00+01:00",
                                     "lastUse": "2026-11-09T08:00:00+01:00", "expiration": None, "allowedIPs": ["203.0.113.7/32"],
                                     "rules": [{"method": "GET", "path": "/domain/zone/sylvain.dev/*"}]})
        if match and self.command == "DELETE":
            return self._reply(200, None)
        return self._reply(404, {"message": "not found"})

    do_GET = do_POST = do_DELETE = _handle


class Base(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), FakeOvh)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.endpoint = f"http://127.0.0.1:{cls.server.server_port}/1.0"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        FakeOvh.requests, FakeOvh.fail = [], None
        self.sops_calls = []

    def sops(self, rc=0, stderr=""):
        def run(cmd, **kwargs):
            self.sops_calls.append((cmd, kwargs))
            return subprocess.CompletedProcess(cmd, rc, stdout="", stderr=stderr)
        return run

    def main(self, argv, run=None, ask=lambda _: ""):
        """Runs main with the real print, stdout and stderr captured, and checks nothing is logged."""
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr), self.assertNoLogs(level="DEBUG"):
            rc = oc.main(argv, env=ENV, endpoint=self.endpoint, run=run or self.sops(), ask=ask)
        self.out, self.err = stdout.getvalue(), stderr.getvalue()
        for secret in SECRETS:
            self.assertNotIn(secret, self.out + self.err)
        return rc

    def methods(self):
        return [(m, p.removeprefix("/1.0")) for m, p, _, _ in FakeOvh.requests]


class List(Base):
    def test_lists_credentials_marks_current_and_signs(self):
        self.assertEqual(self.main(["list"]), 0)
        self.assertRegex(self.out, rf"\* {CURRENT} validated")
        self.assertRegex(self.out, rf"(?m)^  {OLD} validated application 7 « app-7 » \(tofu\) \[rotation\]")
        self.assertRegex(self.out, rf"(?m)^  {OTHER} validated application 9 « app-9 » \(nas-proxy DNS-01\) \[AUTRE APPLICATION")
        self.assertIn("GET /domain/zone/sylvain.dev/*", self.out)
        self.assertIn("IP 203.0.113.7/32", self.out)
        self.assertNotIn(AK, self.out)  # the application's applicationKey is never printed
        _, path, headers, body = FakeOvh.requests[0]
        expected = oc.signature(AS, CK, "GET", f"http://127.0.0.1:{self.server.server_port}{path}", body, headers["X-Ovh-Timestamp"])
        self.assertEqual(headers["X-Ovh-Signature"], expected)
        self.assertEqual(headers["X-Ovh-Application"], AK)

    def test_missing_env_stops_before_any_call(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            self.assertEqual(oc.main(["list"], env={}, endpoint=self.endpoint), 2)
        self.assertIn("OVH_CONSUMER_KEY", stderr.getvalue())
        self.assertEqual(FakeOvh.requests, [])


class Renew(Base):
    def test_requests_rules_writes_sops_by_stdin_then_shows_url(self):
        self.assertEqual(self.main(["renew", "--sops", "/usr/bin/sops"]), 0)
        method, path, headers, body = FakeOvh.requests[0]
        self.assertEqual((method, path), ("POST", "/1.0/auth/credential"))
        self.assertNotIn("X-Ovh-Consumer", headers)  # unsigned: the application key only
        sent = json.loads(body)
        self.assertEqual(sent["allowedIPs"], ["203.0.113.7/32"])
        self.assertEqual(sent["accessRules"], oc.access_rules("proj123"))
        self.assertIn({"method": "DELETE", "path": "/cloud/project/proj123/*"}, sent["accessRules"])
        self.assertNotIn({"method": "POST", "path": "/me/api/credential/*"}, sent["accessRules"])
        [(cmd, kwargs)] = self.sops_calls
        self.assertEqual(cmd, ["/usr/bin/sops", "set", "--value-stdin", "secrets/secrets.sops.yaml", '["OVH_CONSUMER_KEY"]'])
        self.assertEqual(kwargs["input"], json.dumps(NEW_CK))
        self.assertTrue(all(NEW_CK not in part for part in cmd))
        self.assertIn(VALIDATION, self.out)

    def test_allowed_ip_option_wins(self):
        self.main(["renew", "--sops", "sops", "--allowed-ip", "198.51.100.0/24"])
        self.assertEqual(json.loads(FakeOvh.requests[0][3])["allowedIPs"], ["198.51.100.0/24"])

    def test_sops_failure_hides_key_and_url(self):
        rc = self.main(["renew", "--sops", "sops"], run=self.sops(rc=128, stderr=f"Error: cannot set {NEW_CK} {AS}"))
        self.assertEqual(rc, 1)
        self.assertIn("sops set a échoué (128)", self.err)
        self.assertNotIn(VALIDATION, self.out + self.err)

    def test_api_error_echoing_secrets_is_redacted(self):
        FakeOvh.fail = (400, {"errorCode": "BAD", "message": f"refused {AK}:{AS}:{CK}"})
        self.assertEqual(self.main(["renew", "--sops", "sops"]), 1)
        self.assertIn("HTTP 400 BAD refused", self.err)
        self.assertEqual(self.sops_calls, [])


class Revoke(Base):
    def test_refuses_current(self):
        self.assertEqual(self.main(["revoke", str(CURRENT), "--yes"]), 1)
        self.assertIn("en cours", self.out)
        self.assertNotIn("DELETE", [m for m, _ in self.methods()])

    def test_revokes_old_after_typed_confirmation(self):
        self.assertEqual(self.main(["revoke", str(OLD)], ask=lambda _: f"{OLD}\n"), 0)
        self.assertIn(("DELETE", f"/me/api/credential/{OLD}"), self.methods())

    def test_wrong_confirmation_aborts(self):
        self.assertEqual(self.main(["revoke", str(OLD)], ask=lambda _: "y"), 1)
        self.assertNotIn("DELETE", [m for m, _ in self.methods()])

    def test_refuses_another_application_even_with_every_option(self):
        self.assertEqual(self.main(["revoke", str(OTHER), "--force-current", "--yes"]), 1)
        self.assertIn("autre application", self.out)
        self.assertNotIn("DELETE", [m for m, _ in self.methods()])

    def test_force_current(self):
        self.assertEqual(self.main(["revoke", str(CURRENT), "--force-current", "--yes"]), 0)
        self.assertIn(("DELETE", f"/me/api/credential/{CURRENT}"), self.methods())

    def test_api_error_message_and_exception_carry_no_secret(self):
        FakeOvh.fail = (403, {"errorCode": "INVALID_CREDENTIAL", "message": f"consumer {CK} unknown"})
        self.assertEqual(self.main(["revoke", str(OLD), "--yes"]), 1)
        client = oc.Client(AK, AS, CK, endpoint=self.endpoint)
        with self.assertRaises(oc.OvhError) as caught:
            client.call("GET", "/auth/currentCredential")
        self.assertFalse(any(s in repr(caught.exception) for s in SECRETS))
        self.assertTrue(caught.exception.__suppress_context__)  # the HTTPError is not chained into a traceback

    def test_unreachable_api_names_only_the_error_class(self):
        client = oc.Client(AK, AS, CK, endpoint="http://127.0.0.1:9")
        with self.assertRaises(oc.OvhError) as caught:
            client.call("GET", "/auth/currentCredential")
        self.assertIn("URLError", str(caught.exception))


class Zones(unittest.TestCase):
    def test_zones_match_the_tofu_modules(self):
        """ZONES = every zone written by the modules of the root OVH key, no more."""
        tofu = Path(oc.ROOT) / "tofu"
        found = set()
        for module in ("dns", "ref", "site", "1y", "planning"):
            for tf in (tofu / module).glob("*.tf"):
                text = tf.read_text(encoding="utf-8")
                found |= set(re.findall(r'^\s*zone\s*=\s*"([^"$]+)"', text, re.MULTILINE))
                found |= set(re.findall(r'variable "domain_zone"[^}]*?default\s*=\s*"([^"]+)"', text, re.DOTALL))
                found |= set(re.findall(r'^\s*"([a-z0-9.-]+)"\s*=\s*\{\s*p\s*=', text, re.MULTILINE))  # dmarc_policies
        self.assertEqual(found, set(oc.ZONES))


if __name__ == "__main__":
    unittest.main()
