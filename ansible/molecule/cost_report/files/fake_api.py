"""Fausses API du scénario cost_report, sur 127.0.0.1 : Hetzner Cloud
(/cloud), Hetzner (/api, Storage Box) et ntfy (POST /). Chaque
requête ajoute une ligne JSON (méthode, chemin, en-têtes d'authentification,
corps) au fichier donné."""

import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = sys.argv[2]


def price(gross):
    return [{"location": "fsn1", "price_hourly": {"net": "0", "gross": "0"},
             "price_monthly": {"net": "0", "gross": gross}}]


ROUTES = {
    "/cloud/pricing": {"pricing": {
        "currency": "EUR",
        "server_backup": {"percentage": "20.0000000000"},
        "volume": {"price_per_gb_month": {"net": "0.044", "gross": "0.0500000000"}},
        "primary_ips": [{"type": "ipv4", "prices": price("0.6100000000")}],
    }},
    "/cloud/servers": {"servers": [
        {"name": "pangolin", "backup_window": "22-02", "datacenter": {"location": {"name": "fsn1"}},
         "server_type": {"name": "cx22", "prices": price("4.5100000000")}},
        {"name": "flip", "backup_window": None, "location": {"name": "fsn1"},
         "server_type": {"name": "cx32", "prices": price("8.0000000000")}},
    ]},
    "/cloud/primary_ips": {"primary_ips": [
        {"name": "pangolin-v4", "type": "ipv4", "datacenter": {"location": {"name": "fsn1"}}},
    ]},
    "/cloud/volumes": {"volumes": [{"name": "data", "size": 10, "location": {"name": "fsn1"}}]},
    "/api/storage_boxes": {"storage_boxes": [
        {"name": "backups", "location": {"name": "fsn1"}, "storage_box_type": {"name": "bx11", "prices": price("3.8100000000")}},
    ]},
}
AUTH_HEADERS = ("Authorization",)


class Handler(BaseHTTPRequestHandler):
    def record(self, body=None):
        entry = {"method": self.command, "path": self.path,
                 "headers": {name: self.headers[name] for name in AUTH_HEADERS if self.headers[name]}}
        if body is not None:
            entry["body"] = body
        with open(LOG, "a") as log:
            log.write(json.dumps(entry, ensure_ascii=False) + "\n")

    def reply(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):  # noqa: N802 (nom imposé par http.server)
        self.record()
        path = self.path.split("?", 1)[0]
        if path in ROUTES:
            self.reply(200, ROUTES[path])
        else:
            self.reply(404, {"error": "inconnu"})

    def do_POST(self):  # noqa: N802
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        self.record(body)
        self.reply(200, {})

    def log_message(self, format, *args):  # noqa: A002
        pass


# Faux serveur local du verify, sur 127.0.0.1 seulement : pas de TLS à tester.
HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()  # NOSONAR
