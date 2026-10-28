#!/usr/bin/python3
"""Faux Uptime Kuma et faux ntfy : chaque requête (méthode, chemin, en-tête
Authorization, corps) est ajoutée en une ligne JSON au fichier donné."""

import http.server
import json
import sys

LOG = sys.argv[2]


class Handler(http.server.BaseHTTPRequestHandler):
    def record(self):
        length = int(self.headers.get("Content-Length") or 0)
        entry = {
            "method": self.command,
            "path": self.path,
            "authorization": self.headers.get("Authorization", ""),
            "body": self.rfile.read(length).decode() if length else "",
        }
        with open(LOG, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry) + "\n")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    do_GET = record
    do_POST = record


http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
