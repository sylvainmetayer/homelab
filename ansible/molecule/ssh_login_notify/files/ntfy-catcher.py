#!/usr/bin/env python3
"""Faux ntfy du scénario Molecule ssh_login_notify.

Écoute 127.0.0.1:18082 et ajoute une ligne JSON par requête reçue à
/var/lib/molecule-push/ntfy.jsonl. Répond 403 hors du topic scripts, comme un
jeton refusé.
"""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = "/var/lib/molecule-push/ntfy.jsonl"


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        record = {
            "path": self.path,
            "priority": self.headers.get("Priority", ""),
            "title": self.headers.get("Title", ""),
            "authorization": self.headers.get("Authorization", ""),
            "body": body.decode("utf-8"),
        }
        with open(LOG, "a", encoding="utf-8") as log:
            log.write(json.dumps(record, ensure_ascii=False) + "\n")
        self.send_response(200 if self.path == "/scripts" else 403)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *args):
        pass


# Boucle locale du conteneur, comme push-catcher.py : aucun secret ne transite.
HTTPServer(("127.0.0.1", 18082), Handler).serve_forever()  # NOSONAR
