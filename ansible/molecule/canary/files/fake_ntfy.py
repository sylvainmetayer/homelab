"""Faux ntfy du scénario canary.

Répond 200 à toute requête et en écrit une ligne JSON par requête dans le
fichier donné en argument : méthode, chemin (requête comprise), en-tête
Authorization, corps.
"""

import http.server
import json
import sys

LOG = sys.argv[1]


class Handler(http.server.BaseHTTPRequestHandler):
    def record(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode() if length else ""
        with open(LOG, "a", encoding="utf-8") as handle:
            handle.write(json.dumps({
                "method": self.command,
                "path": self.path,
                "authorization": self.headers.get("Authorization", ""),
                "body": body,
            }) + "\n")
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"{}")

    do_GET = record
    do_POST = record


# HTTP en clair sur 127.0.0.1, dans le conteneur Molecule seulement.
http.server.HTTPServer(("127.0.0.1", 18082), Handler).serve_forever()  # NOSONAR
