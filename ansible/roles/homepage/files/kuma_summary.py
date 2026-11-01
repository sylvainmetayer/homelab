#!/usr/bin/env python3
"""Résume, en JSON pour le widget customapi de Homepage, l'état des sondes d'Uptime Kuma.

Uptime Kuma n'offre que deux lectures sans session : ses pages de statut,
publiques par nature (pas de page pour les sauvegardes, par décision), et
/metrics, au format Prometheus, derrière une clé d'API qui n'ouvre rien
d'autre. Homepage ne lit pas ce format : ce serveur interroge /metrics (la
clé ne quitte pas son environnement), ne garde que la jauge monitor_status
(1 en ligne, 0 en panne, 2 en attente, 3 en maintenance) avec le nom et le
type de chaque sonde, et sert :

- /down.json : {"items": [{"name", "status"}], "down", "monitors"}, les
  sondes en panne (ni les dossiers, type group, qui doublent leurs sondes,
  ni les sondes en pause, absentes de /metrics) ; aucune, un seul élément
  « Toutes les sondes » ;
- /backups.json : {"items": [{"name", "status"}], "late"}, une ligne par
  sonde push dont le nom commence par le préfixe des sauvegardes
  (« Backup ») : « OK » tant que la sauvegarde a poussé dans sa fenêtre,
  les autres en premier.

Configuration, par variables d'environnement : KUMA_METRICS_URL (https://…
/metrics), KUMA_API_KEY, KUMA_SUMMARY_PORT (8080),
KUMA_SUMMARY_CACHE_SECONDS (60), KUMA_BACKUP_PREFIX (« Backup »).

/healthz répond 200 sans toucher à Uptime Kuma. Sans dépendance hors de la
bibliothèque standard.

`kuma_summary.py --parse < metrics.txt` imprime les deux résumés (tests).
"""

import base64
import http.client
import json
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Plafond de /metrics (quelques centaines de Kio pour une centaine de
# sondes) : au-delà, refus plutôt qu'un conteneur à 64 Mio poussé au bout.
MAX_BYTES = 8 * 1024 * 1024
FETCH_TIMEOUT = 20

STATUS_DOWN, STATUS_UP, STATUS_PENDING, STATUS_MAINTENANCE = 0, 1, 2, 3
BACKUP_LABELS = {
    STATUS_UP: "OK",
    STATUS_DOWN: "En retard",
    STATUS_PENDING: "En attente",
    STATUS_MAINTENANCE: "Maintenance",
}

SAMPLE = re.compile(r"^monitor_status\{(?P<labels>.*)\}\s+(?P<value>\S+)(?:\s+\d+)?$")
LABEL = re.compile(r'(?P<name>[A-Za-z_][A-Za-z0-9_]*)="(?P<value>(?:[^"\\]|\\.)*)"\s*,?\s*')
ESCAPES = {"\\\\": "\\", '\\"': '"', "\\n": "\n"}


def _unescape(value: str) -> str:
    return re.sub(r"\\[\\\"n]", lambda match: ESCAPES[match.group()], value)


def parse_labels(text: str) -> dict:
    """Étiquettes d'un échantillon Prometheus ; ValueError si mal formées."""
    labels = {}
    position = 0
    while position < len(text):
        match = LABEL.match(text, position)
        if not match:
            raise ValueError("étiquettes mal formées")
        labels[match.group("name")] = _unescape(match.group("value"))
        position = match.end()
    return labels


def parse_monitors(text: str) -> list:
    """[{name, type, status}] des jauges monitor_status de text ; les lignes illisibles sont ignorées."""
    monitors = []
    for line in text.splitlines():
        match = SAMPLE.match(line.strip())
        if not match:
            continue
        try:
            labels = parse_labels(match.group("labels"))
            status = int(float(match.group("value")))
        except ValueError:
            continue
        name = labels.get("monitor_name", "")
        if name:
            monitors.append({"name": name, "type": labels.get("monitor_type", ""), "status": status})
    return monitors


def summarize_down(monitors: list) -> dict:
    probes = [monitor for monitor in monitors if monitor["type"] != "group"]
    down = sorted(monitor["name"] for monitor in probes if monitor["status"] == STATUS_DOWN)
    items = [{"name": name, "status": "En panne"} for name in down]
    if not items:
        items = [{"name": "Toutes les sondes", "status": f"en ligne ({len(probes)})"}]
    return {"items": items, "down": len(down), "monitors": len(probes)}


def summarize_backups(monitors: list, prefix: str) -> dict:
    backups = []
    for monitor in monitors:
        if monitor["type"] == "push" and monitor["name"].startswith(prefix):
            name = monitor["name"][len(prefix):].strip() or monitor["name"]
            # Les sauvegardes qui ne sont pas « OK » d'abord, puis par nom.
            backups.append((monitor["status"] == STATUS_UP, name.casefold(), name, monitor["status"]))
    items = [
        {"name": name, "status": BACKUP_LABELS.get(status, "Inconnu")}
        for _, _, name, status in sorted(backups)
    ]
    return {"items": items, "late": sum(1 for ok, *_ in backups if not ok)}


class FetchError(Exception):
    """/metrics injoignable ou refusé ; le message ne cite ni l'URL ni la clé."""


def fetch(url: str, key: str) -> str:
    if not url.startswith("https://"):
        raise FetchError("URL d'Uptime Kuma pas en https")
    # Basic : Uptime Kuma lit la clé dans le mot de passe, ignore l'utilisateur.
    token = base64.b64encode(f"homepage:{key}".encode()).decode()
    request = urllib.request.Request(
        url, headers={"User-Agent": "homepage-kuma-summary", "Authorization": f"Basic {token}"}
    )
    try:
        with urllib.request.urlopen(request, timeout=FETCH_TIMEOUT) as response:  # noqa: S310 (https vérifié)
            # urllib suit une redirection vers http:// : refusée aussi.
            if not response.url.startswith("https://"):
                raise FetchError("redirection hors de https")
            data = response.read(MAX_BYTES + 1)
    except urllib.error.HTTPError as err:
        raise FetchError(f"HTTP {err.code}") from None
    except (urllib.error.URLError, OSError, http.client.HTTPException, ValueError) as err:
        raise FetchError(type(err).__name__) from None
    if len(data) > MAX_BYTES:
        raise FetchError("réponse trop grosse")
    text = data.decode("utf-8", errors="replace")
    if "monitor_status" not in text:
        # Une page de connexion ou d'erreur n'est pas /metrics.
        raise FetchError("réponse sans monitor_status")
    return text


class Cache:
    """Les sondes lues, gardées ttl secondes ; périmées, servies si Uptime Kuma tombe."""

    def __init__(self, url: str, key: str, ttl: float, fetcher=fetch, clock=time.monotonic):
        self.url = url
        self.key = key
        self.ttl = ttl
        self.fetcher = fetcher
        self.clock = clock
        self.entry = None
        self.lock = threading.Lock()

    def monitors(self) -> list:
        with self.lock:
            now = self.clock()
            if self.entry and now - self.entry[0] < self.ttl:
                return self.entry[1]
            try:
                monitors = parse_monitors(self.fetcher(self.url, self.key))
            except FetchError as err:
                if self.entry:
                    log(f"/metrics : {err}, copie de {int(now - self.entry[0])} s servie")
                    return self.entry[1]
                raise
            self.entry = (now, monitors)
            return monitors


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def make_handler(cache: Cache, prefix: str):
    routes = {
        "/down.json": summarize_down,
        "/backups.json": lambda monitors: summarize_backups(monitors, prefix),
    }

    class Handler(BaseHTTPRequestHandler):
        server_version = "kuma-summary"
        sys_version = ""

        def do_GET(self):  # noqa: N802 (nom imposé par http.server)
            path = self.path.split("?", 1)[0]
            if path == "/healthz":
                self.reply(200, b"ok\n", "text/plain; charset=utf-8")
                return
            summarize = routes.get(path)
            if summarize is None:
                self.reply(404, b"inconnu\n", "text/plain; charset=utf-8")
                return
            try:
                monitors = cache.monitors()
            except FetchError as err:
                log(f"/metrics : {err}")
                self.reply(502, b'{"error": "Uptime Kuma indisponible"}\n', "application/json")
                return
            body = json.dumps(summarize(monitors), ensure_ascii=False).encode()
            self.reply(200, body, "application/json; charset=utf-8")

        def reply(self, status: int, body: bytes, content_type: str) -> None:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format, *args):  # noqa: A002 (signature de http.server)
            log(f"{self.address_string()} {format % args}")

    return Handler


def main() -> int:
    prefix = os.environ.get("KUMA_BACKUP_PREFIX", "Backup ")
    if sys.argv[1:] == ["--parse"]:
        monitors = parse_monitors(sys.stdin.read())
        print(json.dumps({"down": summarize_down(monitors), "backups": summarize_backups(monitors, prefix)},
                         ensure_ascii=False, indent=2))
        return 0
    url = os.environ.get("KUMA_METRICS_URL", "")
    key = os.environ.get("KUMA_API_KEY", "")
    port = int(os.environ.get("KUMA_SUMMARY_PORT", "8080"))
    ttl = float(os.environ.get("KUMA_SUMMARY_CACHE_SECONDS", "60"))
    cache = Cache(url, key, ttl)
    server = ThreadingHTTPServer(("", port), make_handler(cache, prefix))
    log(f"kuma-summary sur le port {port}")
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
