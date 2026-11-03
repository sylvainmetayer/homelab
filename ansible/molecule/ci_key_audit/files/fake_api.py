"""Faux services du scénario ci_key_audit, sur 127.0.0.1 : VictoriaLogs, GitHub,
ntfy, Uptime Kuma. Le fichier de scénario (JSON, relu à chaque requête) dit ce
qu'ils répondent ; chaque requête ajoute une ligne JSON au journal.

Usage : fake_api.py <port> <scénario> <journal>
"""

import datetime
import json
import re
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

SCENARIO = sys.argv[2]
LOG = sys.argv[3]


# Par rapport au démarrage : une même ligne garde sa date d'un passage à l'autre.
STARTED = datetime.datetime.now(datetime.timezone.utc)


def ago(seconds):
    moment = STARTED - datetime.timedelta(seconds=seconds)
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


class Handler(BaseHTTPRequestHandler):
    def scenario(self):
        with open(SCENARIO, encoding="utf-8") as file:
            return json.load(file)

    def record(self, route, **fields):
        entry = {"route": route, "method": self.command, "path": self.path,
                 "authorization": self.headers.get("Authorization", ""), **fields}
        with open(LOG, "a", encoding="utf-8") as log:
            log.write(json.dumps(entry, ensure_ascii=False) + "\n")

    def reply(self, status, data=b"{}"):
        self.send_response(status)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def logs(self, form, scenario):
        query = form["query"][0]
        self.record("logs", query=query, start=form["start"][0])
        if scenario.get("logs_status", 200) != 200:
            self.reply(scenario["logs_status"])
        elif query.startswith("identifier"):
            rows = [{"_time": ago(row["ago"]), "host": row["host"], "_msg": row["msg"]} for row in scenario["lines"]]
            self.reply(200, "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows).encode())
        else:
            rows = [{"host": host, "n": "1"} for host in scenario["fresh"]]
            self.reply(200, "".join(json.dumps(row) + "\n" for row in rows).encode())

    def do_POST(self):  # noqa: N802 (nom imposé par http.server)
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        scenario = self.scenario()
        if self.path == "/select/logsql/query":
            self.logs(urllib.parse.parse_qs(raw.decode()), scenario)
        else:
            self.record("ntfy", body=json.loads(raw))
            self.reply(scenario.get("ntfy_status", 200))

    def do_GET(self):  # noqa: N802
        url = urllib.parse.urlsplit(self.path)
        scenario = self.scenario()
        if url.path.startswith("/api/push/"):
            query = urllib.parse.parse_qs(url.query)
            self.record("push", status=query["status"][0], msg=query["msg"][0])
            self.reply(200)
            return
        self.record("github")
        if scenario.get("github_status", 200) != 200:
            self.reply(scenario["github_status"])
        elif re.search(r"/attempts/\d+/jobs$", url.path):
            self.reply(200, json.dumps({"jobs": [{"steps": scenario["steps"]}]}).encode())
        else:
            runs = [
                {"id": run["id"], "status": "completed", "run_attempt": 1, "created_at": ago(run["start"]),
                 "run_started_at": ago(run["start"]), "updated_at": ago(run["end"])}
                for run in scenario["runs"]
            ]
            self.reply(200, json.dumps({"workflow_runs": runs}).encode())

    def log_message(self, format, *args):  # noqa: A002
        pass


# Faux serveur local du verify, sur 127.0.0.1 seulement : pas de TLS à tester.
HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()  # NOSONAR
