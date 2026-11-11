#!/usr/bin/env python3
"""Stand-in for the Beszel 0.21.1 hub API, for the beszel Molecule scenario.

The scenario never pulls the hub image, so this answers on 127.0.0.1:8090 the
few PocketBase / Beszel routes the role calls, with the semantics of
internal/users/users.go: auth-with-password on _superusers (with the hub's
superuser IP allowlist: 403 for a valid superuser from elsewhere), the admin
user looked up by e-mail, the systems listed from config.yml (as the hub
syncs them at start), alert records created, patched and deleted through the
alerts collection (the superuser sets the user field), user_settings whose
emails the hub fills on create, and test-notification. Every write is appended to WRITES_LOG, and
GET /mock/state dumps the state for verify.yml.

Reads its seed from CONFIG_JSON (written by prepare.yml).
"""

import json
import re
import secrets
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

CONFIG_YML = "/opt/apps/beszel/beszel_data/config.yml"
CONFIG_JSON = "/etc/beszel-api-mock/config.json"
WRITES_LOG = "/var/lib/beszel-api-mock/writes.jsonl"
# Superusers written by beszel_superuser_mock.py, the stand-in of
# `beszel superuser upsert` (email -> password).
SUPERUSERS_JSON = "/var/lib/beszel-superuser-mock/superusers.json"
LOCK = threading.Lock()


def system_id(name):
    """Deterministic 15-character PocketBase-like id of a system name."""
    return ("sys" + re.sub(r"[^a-z0-9]", "", name.lower()) + "0" * 15)[:15]


def declared_systems():
    """Systems of config.yml, as the hub creates them at start."""
    try:
        with open(CONFIG_YML, encoding="utf-8") as f:
            names = re.findall(r"^ {2}- name: (.+)$", f.read(), flags=re.M)
    except FileNotFoundError:
        return []
    return [{"id": system_id(json.loads(n)), "name": json.loads(n)} for n in names]


class State:
    def __init__(self, config):
        self.email = config["email"]
        self.user_id = config["user_id"]
        # The hub's Settings.SuperuserIPs (empty: no restriction).
        self.superuser_ips = config.get("superuser_ips", [])
        # Superusers the allowlist does not apply to: the real hub sees the
        # role's address in its list (added by hand), the Homepage client's
        # address too, but this mock sees one address for both.
        self.superuser_exempt = config.get("superuser_exempt", [])
        self.token = secrets.token_hex(16)
        self.next_id = 0
        self.alerts = []
        for alert in config.get("alerts", []):
            self.add_alert(self.user_id, system_id(alert["system"]), alert["name"], alert["value"], alert["min"])
        self.settings = [
            {"id": record["id"], "user": self.user_id, "settings": record["settings"]}
            for record in config.get("user_settings", [])
        ]

    def new_id(self):
        self.next_id += 1
        return "rec%012d" % self.next_id

    def add_alert(self, user, system, name, value, minutes):
        record = {"id": self.new_id(), "user": user, "system": system,
                  "name": name, "value": value, "min": minutes}
        self.alerts.append(record)
        return record


class Handler(BaseHTTPRequestHandler):
    state = None

    def log_message(self, *args):
        # Silence the per-request stderr lines: journald would only get noise.
        return

    def reply(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(length) or b"{}")

    def authorized(self):
        return self.headers.get("Authorization") == self.state.token

    def record_write(self, data):
        with open(WRITES_LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps({"method": self.command, "path": self.path, "body": data}) + "\n")

    # Routes reachable without the login token.
    def get_health(self, _path):
        return self.reply(200, {"code": 200, "message": "API is healthy."})

    def get_state(self, _path):
        return self.reply(200, {"alerts": self.state.alerts, "user_settings": self.state.settings})

    def post_superuser_login(self, _path):
        data = self.body()
        try:
            with open(SUPERUSERS_JSON, encoding="utf-8") as f:
                superusers = json.load(f)
        except FileNotFoundError:
            superusers = {}
        password = data.get("password")
        if not password or superusers.get(data.get("identity")) != password:
            return self.reply(400, {"message": "Failed to authenticate."})
        # PocketBase checks the password first, then Settings.SuperuserIPs
        # against the request's real IP (apis/record_helpers.go): a valid
        # superuser from an address off the list gets a bare 403.
        allowed = self.state.superuser_ips
        if allowed and data.get("identity") not in self.state.superuser_exempt \
                and self.client_address[0] not in allowed:
            return self.reply(403, {"message": "You are not allowed to perform this request."})
        # Nothing of the request echoed back: the role only reads the status.
        return self.reply(200, {"token": self.state.token, "record": {"collectionName": "_superusers"}})

    # Authenticated reads.
    def get_systems(self, _path):
        return self.reply(200, {"items": declared_systems()})

    def get_users(self, _path):
        # The role filters on role="admin" (one admin account).
        wanted = parse_qs(urlparse(self.path).query).get("filter", [""])[0]
        found = wanted == 'role="admin"'
        return self.reply(200, {"items": [{"id": self.state.user_id, "email": self.state.email}] if found else []})

    def get_alerts(self, _path):
        return self.reply(200, {"items": self.state.alerts})

    def get_settings(self, _path):
        return self.reply(200, {"items": self.state.settings})

    # Authenticated writes: each one is appended to WRITES_LOG first.
    def post_alert(self, data):
        known = {s["id"] for s in declared_systems()}
        if not (data.get("user") and data.get("name") and data.get("system") in known):
            return self.reply(400, {"message": "Failed to create record."})
        # The collection's unique index on (user, system, name).
        if any(a["user"] == data["user"] and a["system"] == data["system"] and a["name"] == data["name"]
               for a in self.state.alerts):
            return self.reply(400, {"message": "Failed to create record."})
        return self.reply(200, self.state.add_alert(
            data["user"], data["system"], data["name"], float(data["value"]), int(data["min"])))

    def patch_alert(self, data, record_id):
        for alert in self.state.alerts:
            if alert["id"] == record_id:
                alert.update({k: data[k] for k in ("value", "min") if k in data})
                return self.reply(200, alert)
        return self.reply(404, {"message": "The requested resource wasn't found."})

    def delete_alert(self, record_id):
        before = len(self.state.alerts)
        self.state.alerts = [a for a in self.state.alerts if a["id"] != record_id]
        if len(self.state.alerts) == before:
            return self.reply(404, {"message": "The requested resource wasn't found."})
        self.send_response(204)
        self.end_headers()

    def post_settings(self, data):
        st = self.state
        settings = dict(data.get("settings") or {}, emails=[st.email])
        settings.setdefault("chartTime", "1h")
        record = {"id": st.new_id(), "user": data["user"], "settings": settings}
        st.settings.append(record)
        return self.reply(200, record)

    def patch_settings(self, data, record_id):
        for record in self.state.settings:
            if record["id"] == record_id:
                record["settings"] = data["settings"]
                return self.reply(200, record)
        return self.reply(404, {"message": "The requested resource wasn't found."})

    def post_test_notification(self, data):
        if not data.get("url"):
            return self.reply(400, {"message": "URL is required"})
        return self.reply(200, {"err": False})

    PUBLIC = {
        ("GET", "/api/health"): "get_health",
        ("GET", "/mock/state"): "get_state",
        ("POST", "/api/collections/_superusers/auth-with-password"): "post_superuser_login",
    }
    READS = {
        ("GET", "/api/collections/users/records"): "get_users",
        ("GET", "/api/collections/systems/records"): "get_systems",
        ("GET", "/api/collections/alerts/records"): "get_alerts",
        ("GET", "/api/collections/user_settings/records"): "get_settings",
    }
    WRITES = {
        ("POST", "/api/collections/alerts/records"): "post_alert",
        ("POST", "/api/collections/user_settings/records"): "post_settings",
        ("POST", "/api/beszel/test-notification"): "post_test_notification",
    }
    SETTINGS_PREFIX = "/api/collections/user_settings/records/"
    ALERTS_PREFIX = "/api/collections/alerts/records/"

    def handle_any(self):
        path = urlparse(self.path).path
        key = (self.command, path)
        if key in self.PUBLIC:
            return getattr(self, self.PUBLIC[key])(path)
        if not self.authorized():
            return self.reply(401, {"message": "The request requires valid record authorization token."})
        if key in self.READS:
            return getattr(self, self.READS[key])(path)
        data = self.body()
        self.record_write(data)
        if key in self.WRITES:
            return getattr(self, self.WRITES[key])(data)
        if self.command == "PATCH" and path.startswith(self.ALERTS_PREFIX):
            return self.patch_alert(data, path[len(self.ALERTS_PREFIX):])
        if self.command == "DELETE" and path.startswith(self.ALERTS_PREFIX):
            return self.delete_alert(path[len(self.ALERTS_PREFIX):])
        if self.command == "PATCH" and path.startswith(self.SETTINGS_PREFIX):
            return self.patch_settings(data, path[len(self.SETTINGS_PREFIX):])
        return self.reply(404, {"message": "Not found."})

    def do_request(self):
        with LOCK:
            self.handle_any()

    do_GET = do_POST = do_PATCH = do_DELETE = do_request


def main():
    with open(CONFIG_JSON, encoding="utf-8") as f:
        Handler.state = State(json.load(f))
    # Plain HTTP on loopback, like the real hub the role calls on 127.0.0.1:8090.
    ThreadingHTTPServer(("127.0.0.1", 8090), Handler).serve_forever()  # NOSONAR


if __name__ == "__main__":
    main()
