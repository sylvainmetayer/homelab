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

AK, AS, CK = "ak-fake-0001", "as-secret-fake-0002", "ck-tofu-fake-0003"
NEW_CK, TEMP_CK = "ck-new-fake-0004", "ck-temp-fake-0005"
ENV = {"OVH_APPLICATION_KEY": AK, "OVH_APPLICATION_SECRET": AS, "OVH_CONSUMER_KEY": CK,
       "OVH_CLOUD_PROJECT_ID": "proj123", "home_ip": "203.0.113.7"}
SECRETS = (AK, AS, CK, NEW_CK, TEMP_CK)
# CURRENT: Tofu's credential (OVH_CONSUMER_KEY), created 2026-11-01. OLD: last
# used before that, revocable. RECENT: same application, used after it.
# OTHER: another application (DNS-01 of the NAS). TEMP: the temporary one.
CURRENT, OLD, OTHER, TEMP, RECENT = 222, 111, 333, 444, 555
APPS = {CURRENT: 7, OLD: 7, OTHER: 9, TEMP: 7, RECENT: 7}
LAST_USE = {OLD: "2026-10-30T08:00:00+01:00", RECENT: "2026-11-09T08:00:00+01:00", OTHER: "2026-11-09T08:00:00+01:00"}
CREATED = "2026-11-01T10:00:00+01:00"
VALIDATION = "https://www.ovh.com/auth/sso/api?credentialToken=tok"
CONSUMERS = {CK: CURRENT, TEMP_CK: TEMP}


def credential(cid):
    return {"credentialId": cid, "applicationId": APPS[cid], "status": "validated", "creation": CREATED,
            "lastUse": LAST_USE.get(cid), "expiration": None, "allowedIPs": ["203.0.113.7/32"],
            "rules": [{"method": "GET", "path": "/domain/zone/sylvain.dev/record"}]}


class FakeOvh(BaseHTTPRequestHandler):
    """The /auth and /me/api routes the script calls; records every request.

    requests: (method, path, consumer key, body) of each request; fail: (code,
    body) returned to all; shapes: path -> payload overriding the normal answer.
    Set by Base.setUp."""

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
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode()
        consumer = self.headers.get("X-Ovh-Consumer")
        path = self.path.removeprefix("/1.0")
        FakeOvh.requests.append((self.command, path, consumer, body))
        FakeOvh.headers = dict(self.headers)
        if FakeOvh.fail:
            return self._reply(*FakeOvh.fail)
        if path in FakeOvh.shapes:
            return self._reply(200, FakeOvh.shapes[path])
        if self.command == "POST" and path == "/auth/credential":
            rules = json.loads(body)["accessRules"]
            key = NEW_CK if any(r["path"].startswith("/domain/") for r in rules) else TEMP_CK
            return self._reply(200, {"consumerKey": key, "state": "pendingValidation", "validationUrl": VALIDATION})
        if consumer not in CONSUMERS:
            return self._reply(403, {"errorCode": "INVALID_CREDENTIAL", "message": "bad"})
        if path == "/auth/currentCredential":
            return self._reply(200, credential(CONSUMERS[consumer]))
        if consumer != TEMP_CK:  # Tofu's token reads nothing else
            return self._reply(403, {"errorCode": "NOT_GRANTED_CALL", "message": "not granted"})
        if path == "/auth/logout":
            return self._reply(200, None)
        if path == "/me/api/credential":
            return self._reply(200, [CURRENT, OTHER, OLD, TEMP, RECENT])
        app = re.fullmatch(r"/me/api/credential/(\d+)/application", path)
        if app:
            app_id = APPS[int(app[1])]
            return self._reply(200, {"applicationId": app_id, "applicationKey": AK, "name": f"app-{app_id}",
                                     "description": "nas-proxy DNS-01" if app_id == 9 else "tofu", "status": "active"})
        match = re.fullmatch(r"/me/api/credential/(\d+)", path)
        if match and self.command == "GET":
            return self._reply(200, credential(int(match[1])))
        if match and self.command == "DELETE":
            return self._reply(200, None)
        return self._reply(404, {"message": "not found"})

    do_GET = do_POST = do_DELETE = _handle


def sent():
    """(method, path, consumer) of every request the fake API received."""
    return [(m, p, c) for m, p, c, _ in FakeOvh.requests]


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
        FakeOvh.requests, FakeOvh.fail, FakeOvh.shapes = [], None, {}
        self.sops_calls = []

    def sops(self, rc=0, stderr=""):
        def run(cmd, **kwargs):
            self.sops_calls.append((cmd, kwargs))
            return subprocess.CompletedProcess(cmd, rc, stdout="", stderr=stderr)
        return run

    def main(self, argv, run=None, answers=("",), env=ENV):
        """Runs main with the real print, stdout and stderr captured; checks nothing is logged or leaked."""
        replies = iter(answers)

        def ask(_prompt):
            reply = next(replies, "")
            if isinstance(reply, BaseException):
                raise reply
            return reply

        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr), self.assertNoLogs(level="DEBUG"):
            rc = oc.main(argv, env=env, endpoint=self.endpoint, run=run or self.sops(), ask=ask)
        self.out, self.err = stdout.getvalue(), stderr.getvalue()
        for secret in SECRETS:
            self.assertNotIn(secret, self.out + self.err)
        return rc

    def assert_temp_expired(self):
        self.assertIn(("POST", "/auth/logout", TEMP_CK), sent())

    def assert_nothing_deleted(self):
        self.assertNotIn("DELETE", [m for m, _, _ in sent()])


class List(Base):
    def test_lists_every_credential_with_a_temporary_one_then_expires_it(self):
        self.assertEqual(self.main(["list"]), 0)
        self.assertRegex(self.out, rf"(?m)^\* {CURRENT} validated application 7 « app-7 » \(tofu\) \[rotation\]")
        self.assertRegex(self.out, rf"(?m)^t {TEMP} validated")
        self.assertRegex(self.out, rf"(?m)^  {OTHER} validated application 9 « app-9 » \(nas-proxy DNS-01\) \[AUTRE APPLICATION")
        self.assertIn("IP 203.0.113.7/32", self.out)
        self.assertIn(VALIDATION, self.out)
        temp_rules = json.loads(FakeOvh.requests[0][3])["accessRules"]
        self.assertEqual(temp_rules, oc._rules(oc.TEMP_RULES))
        self.assertNotIn("DELETE", [r["method"] for r in temp_rules])
        self.assertIsNone(FakeOvh.requests[0][2])  # credential request: unsigned
        self.assertTrue(all(c == TEMP_CK for _, p, c in sent() if p.startswith("/me/")))
        self.assert_temp_expired()

    def test_signature(self):
        oc.Client(AK, AS, CK, endpoint=self.endpoint, clock=lambda: 1700000000).call("GET", "/auth/currentCredential")
        headers = FakeOvh.headers
        url = f"{self.endpoint}/auth/currentCredential"
        self.assertEqual(headers["X-Ovh-Timestamp"], "1700000000")
        self.assertEqual(headers["X-Ovh-Signature"], oc.signature(AS, CK, "GET", url, "", 1700000000))
        self.assertEqual(headers["X-Ovh-Application"], AK)

    def test_unexpected_listing_fails_closed_and_still_expires(self):
        FakeOvh.shapes["/me/api/credential"] = {"ids": [1]}
        self.assertEqual(self.main(["list"]), 1)
        self.assertIn("liste d'entiers attendue", self.err)
        self.assert_temp_expired()

    def test_interrupted_at_validation_still_tries_to_expire(self):
        self.assertEqual(self.main(["list"], answers=(KeyboardInterrupt(),)), 130)
        self.assert_temp_expired()
        self.assertNotIn(("GET", "/me/api/credential", TEMP_CK), sent())

    def test_missing_env_stops_before_any_call(self):
        self.assertEqual(self.main(["list"], env={}), 2)
        self.assertIn("OVH_CONSUMER_KEY", self.err)
        self.assertEqual(FakeOvh.requests, [])


class Renew(Base):
    def test_requests_rules_writes_sops_by_stdin_then_shows_url(self):
        self.assertEqual(self.main(["renew", "--sops", "/usr/bin/sops"]), 0)
        method, path, consumer, body = FakeOvh.requests[0]
        self.assertEqual((method, path, consumer), ("POST", "/auth/credential", None))
        sent_body = json.loads(body)
        self.assertEqual(sent_body["allowedIPs"], ["203.0.113.7/32"])
        self.assertEqual(sent_body["accessRules"], oc.access_rules("proj123"))
        [(cmd, kwargs)] = self.sops_calls
        self.assertEqual(cmd, ["/usr/bin/sops", "set", "--value-stdin", "secrets/secrets.sops.yaml", '["OVH_CONSUMER_KEY"]'])
        self.assertEqual(kwargs["input"], json.dumps(NEW_CK))
        self.assertTrue(all(NEW_CK not in part for part in cmd))
        self.assertIn(VALIDATION, self.out)

    def test_permanent_rules_hold_provider_init_and_never_manage_credentials(self):
        rules = {(r["method"], r["path"]) for r in oc.access_rules("proj123")}
        self.assertIn(("GET", "/auth/details"), rules)
        self.assertFalse([r for r in rules if r[1].startswith("/me/")])
        self.assertNotIn(("POST", "/auth/logout"), rules)
        self.assertFalse([r for r in rules if r[1] in ("/cloud/project/proj123/*", "/cloud/project/proj123")])

    def test_ip_blocks(self):
        self.main(["renew", "--sops", "sops"], env={**ENV, "home_ip": "2001:db8::1"})
        self.assertEqual(json.loads(FakeOvh.requests[0][3])["allowedIPs"], ["2001:db8::1/128"])
        FakeOvh.requests = []
        self.main(["renew", "--sops", "sops", "--allowed-ip", "198.51.100.0/24"])
        self.assertEqual(json.loads(FakeOvh.requests[0][3])["allowedIPs"], ["198.51.100.0/24"])

    def test_malformed_ip_is_refused_before_any_call(self):
        self.assertEqual(self.main(["renew", "--sops", "sops"], env={**ENV, "home_ip": "203.0.113"}), 1)
        self.assertIn("bloc IP mal formé", self.err)
        self.assertEqual(FakeOvh.requests, [])

    def test_sops_failure_hides_key_and_url(self):
        rc = self.main(["renew", "--sops", "sops"], run=self.sops(rc=128, stderr=f"Error: cannot set {NEW_CK} {AS} {AK}"))
        self.assertEqual(rc, 1)
        self.assertIn("sops set a échoué (128)", self.err)
        self.assertNotIn(VALIDATION, self.out + self.err)

    def test_unexpected_answer_fails_closed(self):
        FakeOvh.shapes["/auth/credential"] = ["not", "an", "object"]
        self.assertEqual(self.main(["renew", "--sops", "sops"]), 1)
        self.assertIn("réponse inattendue", self.err)
        self.assertEqual(self.sops_calls, [])

    def test_api_error_echoing_secrets_is_redacted(self):
        FakeOvh.fail = (400, {"errorCode": "BAD", "message": f"refused {AK}:{AS}:{CK}"})
        self.assertEqual(self.main(["renew", "--sops", "sops"]), 1)
        self.assertIn("HTTP 400 BAD refused", self.err)

    def test_clock_drift_hint_on_refused_signature(self):
        FakeOvh.fail = (400, {"errorCode": "INVALID_SIGNATURE", "message": "Invalid signature"})
        self.main(["renew", "--sops", "sops"])
        self.assertIn("horloge locale décalée", self.err)


class Revoke(Base):
    def test_revokes_old_after_typed_confirmation_with_the_temporary_key(self):
        self.assertEqual(self.main(["revoke", str(OLD)], answers=("", f"{OLD}\n")), 0)
        self.assertIn(("DELETE", f"/me/api/credential/{OLD}", TEMP_CK), sent())
        temp_rules = json.loads(FakeOvh.requests[1][3])["accessRules"]
        self.assertIn({"method": "DELETE", "path": "/me/api/credential/*"}, temp_rules)
        self.assert_temp_expired()

    def test_refuses_current(self):
        self.assertEqual(self.main(["revoke", str(CURRENT), "--yes"]), 1)
        self.assertIn("en cours", self.out)
        self.assert_nothing_deleted()
        self.assert_temp_expired()

    def test_refuses_another_application_even_with_every_option(self):
        argv = ["revoke", str(OTHER), "--force-current", "--ignore-recent-use", "--yes"]
        self.assertEqual(self.main(argv), 1)
        self.assertIn("autre application", self.out)
        self.assert_nothing_deleted()

    def test_refuses_recently_used_unless_told(self):
        self.assertEqual(self.main(["revoke", str(RECENT), "--yes"]), 1)
        self.assertIn("un autre système s'en sert encore", self.out)
        self.assert_nothing_deleted()
        FakeOvh.requests = []
        self.assertEqual(self.main(["revoke", str(RECENT), "--yes", "--ignore-recent-use"]), 0)
        self.assertIn(("DELETE", f"/me/api/credential/{RECENT}", TEMP_CK), sent())

    def test_refuses_the_temporary_credential(self):
        self.assertEqual(self.main(["revoke", str(TEMP), "--yes", "--ignore-recent-use"]), 1)
        self.assert_nothing_deleted()

    def test_wrong_confirmation_aborts(self):
        self.assertEqual(self.main(["revoke", str(OLD)], answers=("", "y")), 1)
        self.assert_nothing_deleted()

    def test_force_current(self):
        self.assertEqual(self.main(["revoke", str(CURRENT), "--force-current", "--yes"]), 0)
        self.assertIn(("DELETE", f"/me/api/credential/{CURRENT}", TEMP_CK), sent())

    def test_null_application_ids_fail_closed(self):
        """None == None must not let a revocation through."""
        FakeOvh.shapes["/auth/currentCredential"] = {"credentialId": CURRENT, "applicationId": None, "creation": CREATED}
        self.assertEqual(self.main(["revoke", str(OLD), "--yes"]), 1)
        self.assertIn("applicationId absent ou non entier", self.err)
        self.assertNotIn(("POST", "/auth/credential", None), sent())  # stopped before asking a temporary one
        FakeOvh.requests, FakeOvh.shapes = [], {f"/me/api/credential/{OLD}": {"credentialId": OLD, "status": "validated"}}
        self.assertEqual(self.main(["revoke", str(OLD), "--yes"]), 1)
        self.assert_nothing_deleted()
        self.assert_temp_expired()

    def test_bad_dates_fail_closed(self):
        FakeOvh.shapes[f"/me/api/credential/{RECENT}"] = {**credential(RECENT), "lastUse": "hier"}
        self.assertEqual(self.main(["revoke", str(RECENT), "--yes"]), 1)
        self.assert_nothing_deleted()

    def test_api_error_message_and_exception_carry_no_secret(self):
        FakeOvh.fail = (403, {"errorCode": "INVALID_CREDENTIAL", "message": f"consumer {CK} unknown"})
        self.assertEqual(self.main(["revoke", str(OLD), "--yes"]), 1)
        client = oc.Client(AK, AS, CK, endpoint=self.endpoint)
        with self.assertRaises(oc.OvhError) as caught:
            client.call("GET", "/auth/currentCredential")
        self.assertFalse(any(s in repr(caught.exception) for s in SECRETS))
        self.assertTrue(caught.exception.__suppress_context__)

    def test_unreachable_api_names_only_the_error_class(self):
        client = oc.Client(AK, AS, CK, endpoint="http://127.0.0.1:9")
        with self.assertRaises(oc.OvhError) as caught:
            client.call("GET", "/auth/currentCredential")
        self.assertIn("URLError", str(caught.exception))


class Headers(Base):
    def test_key_with_newline_is_refused_and_masked(self):
        bad = CK + "\nX-Injected: 1"
        self.assertEqual(self.main(["list"], env={**ENV, "OVH_CONSUMER_KEY": bad}), 2)
        self.assertIn("OVH_CONSUMER_KEY", self.err)
        self.assertEqual(FakeOvh.requests, [])
        with self.assertRaises(oc.OvhError) as caught:
            oc.Client(AK, AS, bad, endpoint=self.endpoint).call("GET", "/auth/currentCredential")
        self.assertNotIn(CK, str(caught.exception))
        self.assertIn("X-Ovh-Consumer", str(caught.exception))


TOFU = Path(oc.ROOT) / "tofu"
# Every form a `zone =` takes in the modules, other than a literal; a new one fails the test.
ZONE_REFS = {"each.key", "each.value.zone", "pair.zone", "zone", "var.domain_zone", "local.dmarc_report_domain"}


def ovh_modules():
    return sorted(d for d in TOFU.iterdir() if any('source  = "ovh/ovh"' in f.read_text(encoding="utf-8") for f in d.glob("*.tf")))


class Repository(unittest.TestCase):
    """access_rules() against what the modules of the root OVH key do."""

    def test_provider_version_resources_and_init_routes(self):
        modules = ovh_modules()
        self.assertIn(TOFU / "dns", modules)
        rules = {(r["method"], r["path"]) for r in oc.access_rules("p")}
        for module in modules:
            lock = (module / ".terraform.lock.hcl").read_text(encoding="utf-8")
            version = re.search(r'provider "registry.opentofu.org/ovh/ovh" \{\s*version\s*=\s*"([^"]+)"', lock)
            self.assertEqual(version[1], oc.PROVIDER_VERSION, f"{module.name}: re-read the provider's routes, then bump")
            for tf in module.glob("*.tf"):
                text = tf.read_text(encoding="utf-8")
                self.assertEqual(re.findall(r'^data "(ovh_[a-z0-9_]+)"', text, re.MULTILINE), [], tf)
                self.assertLessEqual(set(re.findall(r'^resource "(ovh_[a-z0-9_]+)"', text, re.MULTILINE)), oc.COVERED_RESOURCES, tf)
        self.assertLessEqual(set(oc.PROVIDER_INIT), rules)

    def test_zones_match_the_tofu_modules(self):
        found, refs = set(), set()
        for module in ovh_modules():
            for tf in [*module.glob("*.tf"), *module.glob("*.tfvars")]:
                text = tf.read_text(encoding="utf-8")
                found |= set(re.findall(r'^\s*zone\s*=\s*"([^"]+)"', text, re.MULTILINE))
                refs |= {r.strip() for r in re.findall(r'^\s*zone\s*=\s*([^"\s][^\n#]*)', text, re.MULTILINE)}
                found |= set(re.findall(r'variable "domain_zone"[^}]*?default\s*=\s*"([^"]+)"', text, re.DOTALL))
                found |= set(re.findall(r'^\s*domain_zone\s*=\s*"([^"]+)"', text, re.MULTILINE))
                found |= set(re.findall(r'variable "dmarc_report_address"[^}]*?default\s*=\s*"[^"@]+@([^"]+)"', text, re.DOTALL))
                for block in re.findall(r"(?:dmarc_policies|caa_issuers)\s*=\s*\{(.*?)\n\s*\}", text, re.DOTALL):
                    found |= set(re.findall(r'^\s*"([a-z0-9.-]+)"\s*=', block, re.MULTILINE))
        self.assertLessEqual(refs, ZONE_REFS, "a new form of `zone =`: teach this test where its value comes from")
        self.assertEqual(found, set(oc.ZONES))


if __name__ == "__main__":
    unittest.main()
