#!/usr/bin/env python3
"""Résume, en JSON pour les widgets customapi de Homepage, ce que ses
widgets natifs ne savent pas lire : Grocy, Papra, Dawarich et les prochains
passages d'un bus TBM.

Chaque source répond en un objet plat, que la carte lit sans calcul :

- /grocy.json : {"due_soon", "overdue", "missing", "chores_overdue"}, les
  produits à consommer bientôt (due_soon_days jours), ceux dont la date est
  passée (à consommer de préférence ou limite), ceux sous leur stock
  minimal et les tâches dont l'échéance est passée (comme la vue des tâches
  de Grocy, à l'heure locale) ; /api/stock/volatile et /api/chores ;
- /papra.json : {"documents", "recent", "untagged"}, tous les documents, ceux
  ajoutés depuis sept jours et ceux sans étiquette, sommés sur les
  organisations de la clé ; /documents/statistics et deux recherches
  (created:>date, -has:tags) dont seul le total est lu ;
- /dawarich.json : {"month_km", "year_km", "year_countries"}, d'après
  /api/v1/stats (statistiques mensuelles que Dawarich recalcule lui-même) ;
- /tbm.json : {"items": [{"name", "status"}]}, les prochains passages d'une
  ligne à des arrêts, par le flux SIRI-lite ouvert de Bordeaux Métropole
  (stop-monitoring), arrêt par arrêt dans l'ordre de la configuration.

Configuration, par variables d'environnement ; une source sans URL (ou sans
clé) n'est pas servie (404) :
APPS_SUMMARY_PORT (8080), APPS_SUMMARY_CACHE_SECONDS (300),
GROCY_URL, GROCY_API_KEY, GROCY_DUE_SOON_DAYS (5),
PAPRA_URL, PAPRA_API_KEY, DAWARICH_URL, DAWARICH_HOST, DAWARICH_API_KEY,
TBM_URL (https:// seulement), TBM_ACCOUNT_KEY, TBM_LINE, TBM_STOPS (arrêts
séparés par des virgules), TBM_DEPARTURES (3), TBM_CACHE_SECONDS (60).
L'heure locale est celle de TZ.

Chaque réponse amont est gardée en cache ; périmée, elle est encore servie
tant que l'amont échoue (502 sans copie). Aucune redirection n'est suivie
(urllib renverrait les en-têtes de la clé à la cible). /healthz répond sans
rien interroger. Bibliothèque standard seulement.

`apps_summary.py --summarize <source> < réponse.json` imprime le résumé
d'une réponse amont enregistrée (tests, débogage).
"""

import datetime
import http.client
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Plafond d'une réponse amont : quelques Kio pour chacune ; au-delà, refus
# plutôt qu'un conteneur à 64 Mio poussé au bout.
MAX_BYTES = 4 * 1024 * 1024
FETCH_TIMEOUT = 20

# Date::MONTHNAMES de Ruby, en minuscules : les clés de monthlyDistanceKm.
MONTHS = ("january", "february", "march", "april", "may", "june", "july",
          "august", "september", "october", "november", "december")


class FetchError(Exception):
    """Amont injoignable ou refusé ; le message ne cite ni l'URL ni la clé."""


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_OPENER = urllib.request.build_opener(_NoRedirect)


def fetch_json(url: str, headers: dict, https_only: bool = False):
    if not url.startswith("https://") and (https_only or not url.startswith("http://")):
        raise FetchError("schéma d'URL refusé")
    request = urllib.request.Request(url, headers={"User-Agent": "homepage-apps-summary", **headers})
    try:
        # Schéma vérifié plus haut, aucune redirection suivie (_NoRedirect).
        with _OPENER.open(request, timeout=FETCH_TIMEOUT) as response:  # noqa: S310
            data = response.read(MAX_BYTES + 1)
    except urllib.error.HTTPError as err:
        raise FetchError(f"HTTP {err.code}") from None
    # URLError dérive d'OSError.
    except (OSError, http.client.HTTPException, ValueError) as err:
        raise FetchError(type(err).__name__) from None
    if len(data) > MAX_BYTES:
        raise FetchError("réponse trop grosse")
    try:
        return json.loads(data)
    except ValueError:
        raise FetchError("réponse illisible") from None


def _count(value) -> int:
    return len(value) if isinstance(value, list) else 0


def _local(now: float, fmt: str) -> str:
    return time.strftime(fmt, time.localtime(now))


# --- Grocy ---------------------------------------------------------------


def summarize_grocy(raw: dict, now: float) -> dict:
    volatile = raw.get("volatile") or {}
    # Grocy écrit ses échéances à l'heure locale, « AAAA-MM-JJ HH:MM:SS » :
    # comparées en texte, comme le fait sa vue des tâches.
    current = _local(now, "%Y-%m-%d %H:%M:%S")
    chores = raw.get("chores") if isinstance(raw.get("chores"), list) else []
    late = [
        chore for chore in chores
        if isinstance(chore, dict) and str(chore.get("next_estimated_execution_time") or "9999") < current
    ]
    return {
        "due_soon": _count(volatile.get("due_products")),
        "overdue": _count(volatile.get("overdue_products")) + _count(volatile.get("expired_products")),
        "missing": _count(volatile.get("missing_products")),
        "chores_overdue": len(late),
    }


def fetch_grocy(env: dict) -> dict:
    base = env["GROCY_URL"].rstrip("/")
    headers = {"GROCY-API-KEY": env["GROCY_API_KEY"], "Accept": "application/json"}
    days = int(env.get("GROCY_DUE_SOON_DAYS") or 5)
    return {
        "volatile": fetch_json(f"{base}/api/stock/volatile?due_soon_days={days}", headers),
        "chores": fetch_json(f"{base}/api/chores", headers),
    }


# --- Papra ---------------------------------------------------------------


def papra_recent_query(now: float) -> str:
    # Papra ne connaît pas de date relative (seulement « now ») : la date
    # d'il y a sept jours, sans heure (le « : » d'une heure gênerait sa
    # syntaxe de recherche), soit minuit UTC.
    since = datetime.datetime.fromtimestamp(now, datetime.timezone.utc).date() - datetime.timedelta(days=7)
    return f"created:>{since.isoformat()}"


def summarize_papra(raw: dict, now: float) -> dict:
    return {key: int(raw.get(key) or 0) for key in ("documents", "recent", "untagged")}


def fetch_papra(env: dict, now: float | None = None) -> dict:
    now = time.time() if now is None else now
    base = env["PAPRA_URL"].rstrip("/")
    headers = {"Authorization": f"Bearer {env['PAPRA_API_KEY']}", "Accept": "application/json"}
    organizations = fetch_json(f"{base}/api/organizations", headers).get("organizations") or []
    totals = {"documents": 0, "recent": 0, "untagged": 0}
    for organization in organizations:
        prefix = f"{base}/api/organizations/{urllib.parse.quote(str(organization['id']), safe='')}/documents"
        stats = fetch_json(f"{prefix}/statistics", headers).get("organizationStats") or {}
        totals["documents"] += int(stats.get("documentsCount") or 0)
        for key, query in (("recent", papra_recent_query(now)), ("untagged", "-has:tags")):
            search = urllib.parse.urlencode({"searchQuery": query, "pageSize": 1})
            totals[key] += int(fetch_json(f"{prefix}?{search}", headers).get("documentsCount") or 0)
    return totals


# --- Dawarich ------------------------------------------------------------


def summarize_dawarich(raw: dict, now: float) -> dict:
    year = int(_local(now, "%Y"))
    month = MONTHS[int(_local(now, "%m")) - 1]
    stats = next(
        (entry for entry in raw.get("yearlyStats") or [] if isinstance(entry, dict) and entry.get("year") == year),
        {},
    )
    return {
        "month_km": int((stats.get("monthlyDistanceKm") or {}).get(month) or 0),
        "year_km": int(stats.get("totalDistanceKm") or 0),
        "year_countries": int(stats.get("totalCountriesVisited") or 0),
    }


def fetch_dawarich(env: dict) -> dict:
    headers = {"Authorization": f"Bearer {env['DAWARICH_API_KEY']}", "Accept": "application/json"}
    # Rails refuse un Host absent d'APPLICATION_HOSTS (le domaine public) :
    # le conteneur est joint par son nom, sous le Host public.
    if env.get("DAWARICH_HOST"):
        headers["Host"] = env["DAWARICH_HOST"]
    return fetch_json(f"{env['DAWARICH_URL'].rstrip('/')}/api/v1/stats", headers)


# --- TBM -----------------------------------------------------------------


def _parse_time(value) -> float | None:
    try:
        return datetime.datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def parse_departures(payload: dict) -> list:
    """[(epoch, destination)] d'une réponse stop-monitoring SIRI-lite."""
    departures = []
    deliveries = ((payload.get("Siri") or {}).get("ServiceDelivery") or {}).get("StopMonitoringDelivery") or []
    for delivery in deliveries:
        for visit in delivery.get("MonitoredStopVisit") or []:
            journey = visit.get("MonitoredVehicleJourney") or {}
            call = journey.get("MonitoredCall") or {}
            when = _parse_time(call.get("ExpectedDepartureTime") or call.get("AimedDepartureTime") or "")
            names = journey.get("DestinationName") or [{}]
            destination = str(names[0].get("value") or "?").title()
            if when is not None:
                departures.append((when, destination))
    return departures


def summarize_tbm(raw: dict, now: float, per_stop: int = 3) -> dict:
    items = []
    for stop in raw.get("stops") or []:
        upcoming = sorted(entry for entry in stop if entry[0] >= now - 30)[:per_stop]
        for when, destination in upcoming:
            minutes = max(0, int((when - now) // 60))
            status = "à l'approche" if minutes < 1 else f"{minutes} min"
            items.append({"name": destination, "status": f"{status} ({_local(when, '%H:%M')})"})
    if not items:
        items = [{"name": "Aucun passage prévu", "status": ""}]
    return {"items": items}


def fetch_tbm(env: dict) -> dict:
    stops = []
    for stop in filter(None, (part.strip() for part in env["TBM_STOPS"].split(","))):
        query = urllib.parse.urlencode(
            {"AccountKey": env.get("TBM_ACCOUNT_KEY", ""), "MonitoringRef": stop, "LineRef": env.get("TBM_LINE", "")}
        )
        stops.append(parse_departures(fetch_json(f"{env['TBM_URL']}?{query}", {}, https_only=True)))
    return {"stops": stops}


# --- Serveur -------------------------------------------------------------


class Source:
    """Une réponse amont gardée ttl secondes ; périmée, servie si l'amont tombe."""

    def __init__(self, name, fetcher, summarize, ttl, clock=time.time):
        self.name = name
        self.fetcher = fetcher
        self.summarize = summarize
        self.ttl = ttl
        self.clock = clock
        self.entry = None
        self.lock = threading.Lock()

    def summary(self) -> dict:
        with self.lock:
            now = self.clock()
            if not (self.entry and now - self.entry[0] < self.ttl):
                try:
                    self.entry = (now, self.fetcher())
                except (FetchError, KeyError, TypeError, AttributeError, ValueError) as err:
                    if not self.entry:
                        raise FetchError(type(err).__name__ if not isinstance(err, FetchError) else str(err)) from None
                    log(f"{self.name} : {err}, copie de {int(now - self.entry[0])} s servie")
            try:
                return self.summarize(self.entry[1], now)
            except (KeyError, TypeError, AttributeError, ValueError, IndexError) as err:
                # Réponse amont d'une forme inattendue : 502, pas une connexion coupée.
                raise FetchError(type(err).__name__) from None


def build_sources(env: dict) -> dict:
    ttl = float(env.get("APPS_SUMMARY_CACHE_SECONDS") or 300)
    sources = {}
    if env.get("GROCY_URL") and env.get("GROCY_API_KEY"):
        sources["/grocy.json"] = Source("grocy", lambda: fetch_grocy(env), summarize_grocy, ttl)
    if env.get("PAPRA_URL") and env.get("PAPRA_API_KEY"):
        sources["/papra.json"] = Source("papra", lambda: fetch_papra(env), summarize_papra, ttl)
    if env.get("DAWARICH_URL") and env.get("DAWARICH_API_KEY"):
        sources["/dawarich.json"] = Source("dawarich", lambda: fetch_dawarich(env), summarize_dawarich, ttl)
    if env.get("TBM_URL") and env.get("TBM_STOPS"):
        per_stop = int(env.get("TBM_DEPARTURES") or 3)
        sources["/tbm.json"] = Source(
            "tbm", lambda: fetch_tbm(env), lambda raw, now: summarize_tbm(raw, now, per_stop),
            float(env.get("TBM_CACHE_SECONDS") or 60),
        )
    return sources


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def make_handler(sources: dict):
    class Handler(BaseHTTPRequestHandler):
        server_version = "apps-summary"
        sys_version = ""

        def do_GET(self):  # noqa: N802 (nom imposé par http.server)
            path = self.path.split("?", 1)[0]
            if path == "/healthz":
                self.reply(200, b"ok\n", "text/plain; charset=utf-8")
                return
            source = sources.get(path)
            if source is None:
                self.reply(404, b"inconnu\n", "text/plain; charset=utf-8")
                return
            try:
                summary = source.summary()
            except FetchError as err:
                log(f"{source.name} : {err}")
                self.reply(502, b'{"error": "source indisponible"}\n', "application/json")
                return
            self.reply(200, json.dumps(summary, ensure_ascii=False).encode(), "application/json; charset=utf-8")

        def reply(self, status: int, body: bytes, content_type: str) -> None:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format, *args):  # noqa: A002 (signature de http.server)
            log(f"{self.address_string()} {format % args}")

    return Handler


SUMMARIZERS = {
    "grocy": summarize_grocy,
    "papra": summarize_papra,
    "dawarich": summarize_dawarich,
    "tbm": lambda payload, now: summarize_tbm({"stops": [parse_departures(payload)]}, now),
}


def main() -> None:
    if len(sys.argv) == 3 and sys.argv[1] == "--summarize" and sys.argv[2] in SUMMARIZERS:
        summary = SUMMARIZERS[sys.argv[2]](json.load(sys.stdin), time.time())
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return
    env = dict(os.environ)
    sources = build_sources(env)
    port = int(env.get("APPS_SUMMARY_PORT") or 8080)
    server = ThreadingHTTPServer(("", port), make_handler(sources))
    log(f"apps-summary sur le port {port} : {', '.join(sorted(sources)) or 'aucune source'}")
    # HTTP sans TLS : sur le réseau newt, sans port publié.
    server.serve_forever()  # NOSONAR


if __name__ == "__main__":
    main()
