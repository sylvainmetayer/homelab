#!/usr/bin/env python3
"""Faux Uptime Kuma du scénario Molecule ssh_login_notify.

Écoute 127.0.0.1:18080 et ajoute une ligne JSON par requête reçue
(chemin, status, msg décodés) à /var/lib/molecule-push/requests.jsonl.
"""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlsplit

LOG = "/var/lib/molecule-push/requests.jsonl"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        url = urlsplit(self.path)
        query = parse_qs(url.query)
        record = {
            "path": url.path,
            "status": query.get("status", [""])[0],
            "msg": query.get("msg", [""])[0],
        }
        with open(LOG, "a", encoding="utf-8") as log:
            log.write(json.dumps(record, ensure_ascii=False) + "\n")
        body = b'{"ok":true}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        # Silencieux : le journal du test, ce sont les push enregistrés, pas
        # les lignes d'accès de http.server.
        pass


# Faux Uptime Kuma du scénario, sur la boucle locale du conteneur : le script
# testé pousse vers cette URL, aucun secret ne transite.
HTTPServer(("127.0.0.1", 18080), Handler).serve_forever()  # NOSONAR
