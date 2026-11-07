"""Faux VictoriaLogs, ntfy et Uptime Kuma du scénario log_alerts, sur 127.0.0.1.

Le fichier de scénario (JSON, relu à chaque requête) donne les lignes de VictoriaLogs
par morceau de requête (le premier présent dans la requête gagne ; `vl_status` force
un code d'erreur) ; chaque requête ajoute une ligne JSON au journal.

Usage : fake_api.py <port> <scénario> <journal>
"""

import json
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

SCENARIO = sys.argv[2]
LOG = sys.argv[3]


class Handler(BaseHTTPRequestHandler):
    def record(self, route, **fields):
        entry = {"route": route, "authorization": self.headers.get("Authorization", ""), **fields}
        with open(LOG, "a", encoding="utf-8") as log:
            log.write(json.dumps(entry, ensure_ascii=False) + "\n")

    def reply(self, status, data=b"{}"):
        self.send_response(status)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):  # noqa: N802 (nom imposé par http.server)
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        with open(SCENARIO, encoding="utf-8") as file:
            scenario = json.load(file)
        if self.path == "/select/logsql/query":
            params = urllib.parse.parse_qs(body)
            query = params["query"][0]
            self.record("vl", query=query, start=params["start"][0])
            if scenario.get("vl_status"):
                return self.reply(scenario["vl_status"])
            rows = next((r for key, r in scenario["vl"].items() if key in query), [])
            return self.reply(200, "".join(json.dumps(row) + "\n" for row in rows).encode())
        self.record("ntfy", body=json.loads(body))
        return self.reply(200)

    def do_GET(self):  # noqa: N802
        url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(url.query)
        self.record("push", path=url.path, status=query["status"][0], msg=query["msg"][0])
        self.reply(200)

    def log_message(self, *_):
        # Muet : le journal des requêtes est celui du scénario.
        pass


HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()  # NOSONAR faux de test, boucle locale
