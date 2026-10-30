#!/usr/bin/env python3
"""Faux Uptime Kuma du scénario Molecule uptime_push, sur la boucle locale.

- 127.0.0.1:18080 rend 200 et ajoute une ligne JSON par requête (chemin,
  status et msg décodés, User-Agent) à /var/lib/molecule-push/requests.jsonl ;
- 127.0.0.1:18081 accepte la connexion TCP sans jamais lire ni répondre : un
  Uptime Kuma qui pend, que uptime-push doit lâcher en 21 s au pire.
"""
import json
import socket
import threading
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
            "agent": self.headers.get("User-Agent", ""),
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
        pass


def blackhole():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", 18081))
    sock.listen(64)
    threading.Event().wait()


threading.Thread(target=blackhole, daemon=True).start()
# Boucle locale du conteneur : aucun secret ne transite.
HTTPServer(("127.0.0.1", 18080), Handler).serve_forever()  # NOSONAR
