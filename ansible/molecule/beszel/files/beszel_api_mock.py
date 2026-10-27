#!/usr/bin/env python3
"""Stand-in for the Beszel 0.21.1 hub API, for the beszel Molecule scenario.

The scenario never pulls the hub image, so this answers on 127.0.0.1:8090 the
few PocketBase / Beszel routes the role calls, with the semantics of
internal/alerts/alerts_api.go and internal/users/users.go: auth-with-password
on the users collection, the systems listed from config.yml (as the hub syncs
them at start), alerts upserted and deleted per user through
/api/beszel/user-alerts, user_settings whose emails the hub fills on create,
and test-notification. Every write is appended to WRITES_LOG, and
GET /mock/state dumps the state for verify.yml.

Usage: beszel_api_mock.py <config.json>
"""

import json
import re
import secrets
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

CONFIG_YML = "/opt/apps/beszel/beszel_data/config.yml"
WRITES_LOG = "/var/lib/beszel-api-mock/writes.jsonl"
LOCK = threading.Lock()


def system_id(name):
    """Deterministic 15-character PocketBase-like id of a system name."""
    return ("sys" + re.sub(r"[^a-z0-9]", "", name.lower()) + "0" * 15)[:15]


def declared_systems():
    """Systems of config.yml, as the hub creates them at start."""
    try:
        with open(CONFIG_YML, encoding="utf-8") as f:
            names = re.findall(r"^  - name: (.+)$", f.read(), flags=re.M)
    except FileNotFoundError:
        return []
    return [{"id": system_id(json.loads(n)), "name": json.loads(n)} for n in names]


class State:
    def __init__(self, config):
        self.email = config["email"]
        self.password = config["password"]
        self.user_id = config["user_id"]
        self.token = secrets.token_hex(16)
        self.next_id = 0
        self.alerts = []
        for alert in config.get("alerts", []):
            self.add_alert(system_id(alert["system"]), alert["name"], alert["value"], alert["min"])
        self.settings = [
            {"id": record["id"], "user": self.user_id, "settings": record["settings"]}
            for record in config.get("user_settings", [])
        ]

    def new_id(self):
        self.next_id += 1
        return "rec%012d" % self.next_id

    def add_alert(self, system, name, value, minutes):
        self.alerts.append(
            {"id": self.new_id(), "user": self.user_id, "system": system,
             "name": name, "value": value, "min": minutes}
        )


class Handler(BaseHTTPRequestHandler):
    state = None

    def log_message(self, *args):
        pass

    def reply(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
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

    def handle_any(self):
        path = urlparse(self.path).path
        st = self.state
        if self.command == "GET" and path == "/api/health":
            return self.reply(200, {"code": 200, "message": "API is healthy."})
        if self.command == "GET" and path == "/mock/state":
            return self.reply(200, {"alerts": st.alerts, "user_settings": st.settings})
        if self.command == "POST" and path == "/api/collections/users/auth-with-password":
            data = self.body()
            if data.get("identity") == st.email and data.get("password") == st.password:
                return self.reply(200, {"token": st.token, "record": {"id": st.user_id, "email": st.email}})
            return self.reply(400, {"message": "Failed to authenticate."})
        if not self.authorized():
            return self.reply(401, {"message": "The request requires valid record authorization token."})

        if self.command == "GET" and path == "/api/collections/systems/records":
            return self.reply(200, {"items": declared_systems()})
        if self.command == "GET" and path == "/api/collections/alerts/records":
            return self.reply(200, {"items": st.alerts})
        if self.command == "GET" and path == "/api/collections/user_settings/records":
            return self.reply(200, {"items": st.settings})

        data = self.body()
        self.record_write(data)
        known = {s["id"] for s in declared_systems()}
        if self.command == "POST" and path == "/api/beszel/user-alerts":
            if not data.get("name") or not data.get("systems"):
                return self.reply(400, {"message": "Bad data"})
            for system in data["systems"]:
                if system not in known:
                    continue
                match = [a for a in st.alerts if a["system"] == system and a["name"] == data["name"]]
                if match and not data.get("overwrite"):
                    continue
                if match:
                    match[0].update(value=float(data.get("value", 0)), min=int(data.get("min", 0)))
                else:
                    st.add_alert(system, data["name"], float(data.get("value", 0)), int(data.get("min", 0)))
            return self.reply(200, {"success": True})
        if self.command == "DELETE" and path == "/api/beszel/user-alerts":
            before = len(st.alerts)
            st.alerts = [a for a in st.alerts
                         if not (a["name"] == data.get("name") and a["system"] in data.get("systems", []))]
            return self.reply(200, {"success": True, "count": before - len(st.alerts)})
        if self.command == "POST" and path == "/api/collections/user_settings/records":
            settings = dict(data.get("settings") or {}, emails=[st.email])
            settings.setdefault("chartTime", "1h")
            record = {"id": st.new_id(), "user": data["user"], "settings": settings}
            st.settings.append(record)
            return self.reply(200, record)
        if self.command == "PATCH" and path.startswith("/api/collections/user_settings/records/"):
            record_id = path.rsplit("/", 1)[1]
            for record in st.settings:
                if record["id"] == record_id:
                    record["settings"] = data["settings"]
                    return self.reply(200, record)
            return self.reply(404, {"message": "The requested resource wasn't found."})
        if self.command == "POST" and path == "/api/beszel/test-notification":
            if not data.get("url"):
                return self.reply(400, {"message": "URL is required"})
            return self.reply(200, {"err": False})
        return self.reply(404, {"message": "Not found."})

    def do_request(self):
        with LOCK:
            self.handle_any()

    do_GET = do_POST = do_PATCH = do_DELETE = do_request


def main():
    with open(sys.argv[1], encoding="utf-8") as f:
        Handler.state = State(json.load(f))
    ThreadingHTTPServer(("127.0.0.1", 8090), Handler).serve_forever()


if __name__ == "__main__":
    main()
