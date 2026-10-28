"""Faux ntfy du scénario mem_report : répond 200 à chaque POST et en ajoute
une ligne JSON (chemin, en-tête Authorization, corps) au fichier donné."""

import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = sys.argv[2]


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802 (nom imposé par http.server)
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        with open(LOG, "a") as log:
            entry = {"path": self.path, "auth": self.headers.get("Authorization", ""), "body": json.loads(body)}
            log.write(json.dumps(entry) + "\n")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b"{}")


HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
