#!/usr/bin/env python3
"""Sert, filtrés, les agendas iCal que lit le widget calendar de Homepage.

Le widget affiche chaque tâche (VTODO) comme un événement daté de
l'instant présent : l'agenda partagé Top nous en a des dizaines, qui
cachent les vrais événements. Ce serveur récupère chaque agenda en amont
(l'URL de partage, secrète, ne quitte pas son environnement), en retire les
composants VTODO et VJOURNAL, et rend le reste tel quel (en-têtes du
VCALENDAR, VTIMEZONE, VEVENT, lignes repliées et fins de ligne d'origine).

Configuration, par variables d'environnement :
- ICAL_FEED_<NOM>=https://… : un agenda, servi en /<nom>.ics, <nom> en
  minuscules, « _ » devenu « - » (ICAL_FEED_TOP_NOUS -> /top-nous.ics) ;
- ICAL_FILTER_PORT (8080), ICAL_FILTER_CACHE_SECONDS (300).

/healthz répond 200 sans toucher aux agendas. Sans dépendance hors de la
bibliothèque standard.

`ical_filter.py --filter < agenda.ics` filtre l'entrée standard (tests).
"""

import os
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DROPPED = {b"VTODO", b"VJOURNAL"}
FEED_PREFIX = "ICAL_FEED_"
# Plafond d'un agenda en amont : au-delà, refus plutôt qu'un conteneur à
# 64 Mio poussé au bout de sa mémoire.
MAX_BYTES = 8 * 1024 * 1024
FETCH_TIMEOUT = 20


def filter_calendar(data: bytes) -> bytes:
    """Retire de data les composants VTODO et VJOURNAL (et ce qu'ils contiennent).

    Travaille sur les lignes logiques (une ligne et ses continuations, qui
    commencent par une espace ou une tabulation) sans les déplier : ce qui
    reste est recopié octet pour octet.
    """
    out = []
    depth = 0  # imbrication dans le composant retiré (VALARM d'un VTODO…)
    lines = data.splitlines(keepends=True)
    i = 0
    while i < len(lines):
        j = i + 1
        while j < len(lines) and lines[j][:1] in (b" ", b"\t"):
            j += 1
        logical = b"".join(line.rstrip(b"\r\n") for line in lines[i:j])
        name, _, value = logical.partition(b":")
        name = name.strip().upper()
        value = value.strip().upper()
        if depth:
            if name == b"BEGIN":
                depth += 1
            elif name == b"END":
                depth -= 1
        elif name == b"BEGIN" and value in DROPPED:
            depth = 1
        else:
            out.extend(lines[i:j])
        i = j
    return b"".join(out)


def feeds_from_env(environ) -> dict:
    """{slug: url} des variables ICAL_FEED_<NOM> non vides."""
    feeds = {}
    for key, url in environ.items():
        if key.startswith(FEED_PREFIX) and url:
            slug = key[len(FEED_PREFIX):].lower().replace("_", "-")
            feeds[slug] = url
    return feeds


class FeedError(Exception):
    """Agenda en amont injoignable ou invalide ; le message ne cite pas l'URL."""


def fetch(url: str) -> bytes:
    if not url.startswith("https://"):
        raise FeedError("URL en amont pas en https")
    request = urllib.request.Request(url, headers={"User-Agent": "homepage-ical-filter"})
    try:
        with urllib.request.urlopen(request, timeout=FETCH_TIMEOUT) as response:  # noqa: S310 (https vérifié)
            data = response.read(MAX_BYTES + 1)
    except urllib.error.HTTPError as err:
        raise FeedError(f"HTTP {err.code}") from None
    except (urllib.error.URLError, OSError) as err:
        raise FeedError(type(err).__name__) from None
    if len(data) > MAX_BYTES:
        raise FeedError("agenda trop gros")
    if not data.lstrip(b"\xef\xbb\xbf \t\r\n").upper().startswith(b"BEGIN:VCALENDAR"):
        # Une page HTML (partage retiré, page de connexion) n'est pas un agenda.
        raise FeedError("réponse sans BEGIN:VCALENDAR")
    return filter_calendar(data)


class Cache:
    """Un agenda filtré par slug, gardé ttl secondes ; périmé, servi si l'amont tombe."""

    def __init__(self, feeds: dict, ttl: float, fetcher=fetch, clock=time.monotonic):
        self.feeds = feeds
        self.ttl = ttl
        self.fetcher = fetcher
        self.clock = clock
        self.entries = {}
        self.lock = threading.Lock()

    def get(self, slug: str) -> bytes:
        # Un seul téléchargement à la fois : deux agendas, quelques lecteurs.
        with self.lock:
            entry = self.entries.get(slug)
            now = self.clock()
            if entry and now - entry[0] < self.ttl:
                return entry[1]
            try:
                body = self.fetcher(self.feeds[slug])
            except FeedError as err:
                if entry:
                    log(f"{slug} : {err}, copie de {int(now - entry[0])} s servie")
                    return entry[1]
                raise
            self.entries[slug] = (now, body)
            return body


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def make_handler(cache: Cache):
    class Handler(BaseHTTPRequestHandler):
        server_version = "ical-filter"
        sys_version = ""

        def do_GET(self):  # noqa: N802 (nom imposé par http.server)
            path = self.path.split("?", 1)[0]
            if path == "/healthz":
                self.reply(200, b"ok\n", "text/plain; charset=utf-8")
                return
            slug = path[1:].removesuffix(".ics") if path.endswith(".ics") else None
            if slug not in cache.feeds:
                self.reply(404, b"agenda inconnu\n", "text/plain; charset=utf-8")
                return
            try:
                body = cache.get(slug)
            except FeedError as err:
                log(f"{slug} : {err}")
                self.reply(502, b"agenda en amont indisponible\n", "text/plain; charset=utf-8")
                return
            self.reply(200, body, "text/calendar; charset=utf-8")

        def reply(self, status: int, body: bytes, content_type: str) -> None:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format, *args):  # noqa: A002 (signature de http.server)
            # Le chemin seul (un slug), jamais l'URL en amont.
            log(f"{self.address_string()} {format % args}")

    return Handler


def main() -> int:
    if sys.argv[1:] == ["--filter"]:
        sys.stdout.buffer.write(filter_calendar(sys.stdin.buffer.read()))
        return 0
    feeds = feeds_from_env(os.environ)
    port = int(os.environ.get("ICAL_FILTER_PORT", "8080"))
    ttl = float(os.environ.get("ICAL_FILTER_CACHE_SECONDS", "300"))
    cache = Cache(feeds, ttl)
    server = ThreadingHTTPServer(("", port), make_handler(cache))
    log(f"ical-filter : {', '.join(sorted(feeds)) or 'aucun agenda'} sur le port {port}")
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
