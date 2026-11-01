#!/usr/bin/python3
"""Rapport mensuel des coûts du homelab, sur ntfy et Homepage (rôle cost_report).

Lancé chaque jour par cost-report.timer. Interroge chaque source configurée :
  - Hetzner (jeton de projet en lecture seule) : serveurs Cloud, leurs
    sauvegardes, IP primaires, volumes et Storage Box, au tarif mensuel TTC
    de l'API (/pricing, prix du type). L'API n'a pas de facture : c'est une
    estimation au tarif courant des ressources présentes aujourd'hui ;
  - OVH (application restreinte à GET /me/bill, /me/bill/* et
    /cloud/project/<id>/usage/current) : les factures du mois (TTC, domaines
    et Public Cloud du mois d'avant compris), plus, pour le mois en cours, la
    consommation Public Cloud pas encore facturée (HT dans l'API, TVA
    ajoutée) ;
  - les abonnements fixes de la configuration (PikaPods, kDrive…), un
    montant par mois ou par an (ramené au mois).
Une source sans clé est « non configurée », un abonnement à 0 « à
renseigner » : le rapport sort quand même, partiel, et le dit.

Écrit chaque jour <state-dir>/costs.json (lu par la carte Coûts de Homepage,
apps-summary) : le total du mois dernier et celui du mois en cours à date
(prorata du mois écoulé pour Hetzner et les abonnements). Publie sur ntfy
le rapport du mois dernier une fois par mois : au premier lancement d'un
mois dont le rapport n'est pas encore parti (le 1er, ou plus tard si
l'hôte était éteint), mémorisé dans <state-dir>/state.json.

Bibliothèque standard seule. Les jetons arrivent par l'environnement
(EnvironmentFile de l'unité, 0600 root), jamais par la ligne de commande,
jamais affichés ; une erreur d'API n'est citée que par son code ou sa classe.
"""

import argparse
import calendar
import datetime
import hashlib
import http.client
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

NTFY_TOKEN = "COST_REPORT_NTFY_TOKEN"
HCLOUD_TOKEN = "COST_REPORT_HCLOUD_TOKEN"
OVH_KEYS = ("COST_REPORT_OVH_APPLICATION_KEY", "COST_REPORT_OVH_APPLICATION_SECRET", "COST_REPORT_OVH_CONSUMER_KEY")
OVH_PROJECT = "COST_REPORT_OVH_CLOUD_PROJECT"

MAX_BYTES = 4 * 1024 * 1024
TIMEOUT = 30
# ntfy refuse un message de plus de 4096 octets (pièces jointes coupées,
# rôle ntfy) : marge pour le JSON.
MAX_MESSAGE = 3800
MONTHS = ("janvier", "février", "mars", "avril", "mai", "juin", "juillet",
          "août", "septembre", "octobre", "novembre", "décembre")
PERIODS = {"monthly": 1, "yearly": 12}

OK = "ok"
UNCONFIGURED = "non configurée"
TO_FILL = "à renseigner"
FAILED = "en erreur"


class SourceError(Exception):
    """Réponse inexploitable ; le message ne cite ni URL ni jeton."""


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


# Aucune redirection suivie : urllib renverrait l'en-tête du jeton à la cible.
_OPENER = urllib.request.build_opener(_NoRedirect)


def fetch_json(url, headers):
    if not url.startswith(("https://", "http://127.0.0.1:")):
        raise SourceError("schéma d'URL refusé")
    request = urllib.request.Request(url, headers={"User-Agent": "homelab-cost-report", "Accept": "application/json", **headers})
    try:
        # Schéma vérifié plus haut, aucune redirection suivie (_NoRedirect).
        with _OPENER.open(request, timeout=TIMEOUT) as response:  # noqa: S310 # NOSONAR
            data = response.read(MAX_BYTES + 1)
    except urllib.error.HTTPError as error:
        raise SourceError(f"HTTP {error.code}") from None
    # URLError dérive d'OSError ; sa classe seule, son message peut citer l'URL.
    except (OSError, http.client.HTTPException, ValueError) as error:
        raise SourceError(type(error).__name__) from None
    if len(data) > MAX_BYTES:
        raise SourceError("réponse trop grosse")
    try:
        return json.loads(data)
    except ValueError:
        raise SourceError("réponse illisible") from None


# --- Mois et montants ----------------------------------------------------


def month_key(day):
    return f"{day.year:04d}-{day.month:02d}"


def previous_month(day):
    first = day.replace(day=1)
    return (first - datetime.timedelta(days=1)).replace(day=1)


def month_label(day):
    return f"{MONTHS[day.month - 1]} {day.year}"


def elapsed_fraction(now):
    """Part du mois de `now` écoulée, de 0 à 1."""
    days = calendar.monthrange(now.year, now.month)[1]
    start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    return min(1.0, max(0.0, (now - start).total_seconds() / (days * 86400)))


def add(total, currency, amount):
    total[currency] = total.get(currency, 0.0) + amount
    return total


def money(value, currency):
    text = f"{value:,.2f}".replace(",", " ").replace(".", ",")
    return f"{text} €" if currency == "EUR" else f"{text} {currency}"


def money_total(amounts):
    """« 12,34 € », ou « 12,34 € + 5,00 USD » : pas de conversion de devise."""
    if not amounts:
        return money(0, "EUR")
    order = sorted(amounts, key=lambda currency: (currency != "EUR", currency))
    return " + ".join(money(amounts[currency], currency) for currency in order)


def result(name, status, previous=None, current=None, lines=(), note=""):
    return {"name": name, "status": status, "previous": previous or {}, "current": current or {},
            "lines": list(lines), "note": note}


# --- Hetzner -------------------------------------------------------------


def _location(resource):
    location = resource.get("location")
    if isinstance(location, dict):
        return location.get("name")
    if isinstance(location, str):
        return location
    return ((resource.get("datacenter") or {}).get("location") or {}).get("name")


def _monthly(prices, location):
    for price in prices or []:
        if price.get("location") == location:
            return float(price["price_monthly"]["gross"])
    raise SourceError(f"pas de prix pour {location}")


def hetzner_items(data):
    """(devise, [(libellé, prix mensuel TTC)]) des ressources du projet."""
    pricing = data["pricing"]["pricing"]
    currency = pricing.get("currency") or "EUR"
    backup = float(pricing["server_backup"]["percentage"]) / 100
    items = []
    for server in data["servers"]:
        price = _monthly(server["server_type"]["prices"], _location(server))
        items.append((f"{server['name']} ({server['server_type']['name']})", price))
        # Sauvegardes actives : un pourcentage du prix du serveur.
        if server.get("backup_window"):
            items.append((f"{server['name']} : sauvegardes", price * backup))
    ip_prices = {entry["type"]: entry.get("prices") for entry in pricing.get("primary_ips") or []}
    for address in data["primary_ips"]:
        prices = ip_prices.get(address["type"])
        # L'IPv6 n'a pas de prix.
        if prices:
            price = _monthly(prices, _location(address))
            if price > 0:
                items.append((f"IP {address['type']} {address['name']}", price))
    per_gb = float(pricing["volume"]["price_per_gb_month"]["gross"])
    for volume in data["volumes"]:
        items.append((f"volume {volume['name']} ({volume['size']} Go)", volume["size"] * per_gb))
    for box in data["storage_boxes"]:
        kind = box["storage_box_type"]
        items.append((f"Storage Box {box['name']} ({kind['name']})", _monthly(kind["prices"], _location(box))))
    return currency, items


def hetzner_result(data, fraction):
    currency, items = hetzner_items(data)
    monthly = sum(price for _, price in items)
    lines = [f"{label} : {money(price, currency)}" for label, price in items]
    return result("Hetzner", OK, {currency: monthly}, {currency: monthly * fraction}, lines,
                  "estimation au tarif courant des ressources actuelles")


def fetch_hetzner(token, cloud_api, api):
    headers = {"Authorization": f"Bearer {token}"}
    cloud_api, api = cloud_api.rstrip("/"), api.rstrip("/")

    def listing(base, name):
        return fetch_json(f"{base}/{name}?per_page=50", headers)[name]

    return {
        "pricing": fetch_json(f"{cloud_api}/pricing", headers),
        "servers": listing(cloud_api, "servers"),
        "primary_ips": listing(cloud_api, "primary_ips"),
        "volumes": listing(cloud_api, "volumes"),
        "storage_boxes": listing(api, "storage_boxes"),
    }


# --- OVH -----------------------------------------------------------------


def ovh_signature(secret, consumer, method, url, body, timestamp):
    """Signature des requêtes de l'API OVH : $1$ + SHA-1 des champs joints par « + »."""
    payload = "+".join((secret, consumer, method, url, body, str(timestamp)))
    # SHA-1 imposé par le protocole de l'API OVH, pas un choix.
    return "$1$" + hashlib.sha1(payload.encode()).hexdigest()  # noqa: S324 # NOSONAR


class OvhClient:
    def __init__(self, endpoint, application_key, application_secret, consumer_key, clock=time.time, fetch=fetch_json):
        self.endpoint = endpoint.rstrip("/")
        self.application_key = application_key
        self.application_secret = application_secret
        self.consumer_key = consumer_key
        self.clock = clock
        self.fetch = fetch

    def get(self, path, params=None):
        url = self.endpoint + path + ("?" + urllib.parse.urlencode(params) if params else "")
        timestamp = int(self.clock())
        headers = {
            "X-Ovh-Application": self.application_key,
            "X-Ovh-Consumer": self.consumer_key,
            "X-Ovh-Timestamp": str(timestamp),
            "X-Ovh-Signature": ovh_signature(self.application_secret, self.consumer_key, "GET", url, "", timestamp),
        }
        return self.fetch(url, headers)


def fetch_ovh(client, project, since, now):
    """Les factures depuis le 1er du mois dernier, et la consommation en cours."""
    ids = client.get("/me/bill", {"date.from": since.isoformat(), "date.to": (now.date() + datetime.timedelta(days=1)).isoformat()})
    # Seuls la date et le montant sont gardés : une facture porte aussi un
    # mot de passe et ses URL.
    bills = []
    for bill_id in ids:
        bill = client.get(f"/me/bill/{urllib.parse.quote(str(bill_id), safe='')}")
        bills.append({"date": bill["date"], "priceWithTax": bill["priceWithTax"]})
    usage = client.get(f"/cloud/project/{urllib.parse.quote(project, safe='')}/usage/current") if project else None
    return {"bills": bills, "usage": usage}


def ovh_result(data, previous_key, current_key, vat_percent):
    previous, current, lines = {}, {}, []
    for bill in data["bills"]:
        price = bill["priceWithTax"]
        key = str(bill["date"])[:7]
        if key == previous_key:
            add(previous, price["currencyCode"], float(price["value"]))
        elif key == current_key:
            add(current, price["currencyCode"], float(price["value"]))
    count = sum(1 for bill in data["bills"] if str(bill["date"])[:7] == previous_key)
    lines.append(f"{count} facture(s) le mois dernier : {money_total(previous)}")
    usage = data.get("usage")
    if usage:
        total = usage["totalPrice"]
        excluding = float(total["value"])
        including = excluding * (1 + vat_percent / 100)
        add(current, total["currencyCode"], including)
        lines.append(f"Public Cloud du mois en cours : {money(excluding, total['currencyCode'])} HT, pas encore facturé")
    return result("OVH", OK, previous, current, lines, "factures émises dans le mois, TTC")


# --- Abonnements ---------------------------------------------------------


def subscription_results(subscriptions, fraction):
    results = []
    for entry in subscriptions:
        months = PERIODS[entry["period"]]
        amount = float(entry["amount"])
        currency = entry["currency"]
        if amount <= 0:
            results.append(result(entry["name"], TO_FILL))
            continue
        monthly = amount / months
        note = "fixe" if months == 1 else f"{money(amount, currency)} par an, ramené au mois"
        results.append(result(entry["name"], OK, {currency: monthly}, {currency: monthly * fraction}, note=note))
    return results


# --- Rapport -------------------------------------------------------------


def collect(config, env, now):
    """Une entrée par source, dans l'ordre : Hetzner, OVH, puis les abonnements."""
    fraction = elapsed_fraction(now)
    last = previous_month(now.date())
    results = []

    token = env.get(HCLOUD_TOKEN, "")
    if not token:
        results.append(result("Hetzner", UNCONFIGURED))
    else:
        try:
            data = fetch_hetzner(token, config["hetzner_cloud_api"], config["hetzner_api"])
            results.append(hetzner_result(data, fraction))
        except (SourceError, KeyError, TypeError, ValueError, AttributeError) as error:
            results.append(result("Hetzner", FAILED, note=describe(error)))

    keys = [env.get(name, "") for name in OVH_KEYS]
    if not all(keys):
        results.append(result("OVH", UNCONFIGURED))
    else:
        try:
            client = OvhClient(config["ovh_endpoint"], *keys)
            data = fetch_ovh(client, env.get(OVH_PROJECT, ""), last, now)
            results.append(ovh_result(data, month_key(last), month_key(now), float(config.get("ovh_vat_percent", 20))))
        except (SourceError, KeyError, TypeError, ValueError, AttributeError) as error:
            results.append(result("OVH", FAILED, note=describe(error)))

    results.extend(subscription_results(config.get("subscriptions") or [], fraction))
    return results


def describe(error):
    return str(error) if isinstance(error, SourceError) else f"réponse inattendue ({type(error).__name__})"


def totals(results, field):
    total = {}
    for entry in results:
        if entry["status"] == OK:
            for currency, amount in entry[field].items():
                add(total, currency, amount)
    return total


def incomplete(results):
    return [entry for entry in results if entry["status"] != OK]


def build_report(results, now):
    """(titre, message, priorité) du rapport du mois dernier."""
    last = previous_month(now.date())
    title = f"Coûts du homelab : {month_label(last)}"
    head = [f"Total : {money_total(totals(results, 'previous'))}"]
    body = []
    for entry in results:
        if entry["status"] == OK:
            note = f" ({entry['note']})" if entry["note"] else ""
            body.append(f"- {entry['name']} : {money_total(entry['previous'])}{note}")
            body.extend(f"    {line}" for line in entry["lines"])
        else:
            note = f" : {entry['note']}" if entry["note"] else ""
            body.append(f"- {entry['name']} : {entry['status']}{note}")
    missing = incomplete(results)
    footer = []
    if missing:
        names = [entry["name"] for entry in missing[:10]] + ([f"{len(missing) - 10} autre(s)"] if len(missing) > 10 else [])
        footer.append(f"Incomplet, sans : {', '.join(names)}.")
    footer.append(f"Mois en cours à date : {money_total(totals(results, 'current'))}.")
    message = fit(head, body, footer)
    priority = 4 if any(entry["status"] == FAILED for entry in results) else 3
    return title, message, priority


def fit(head, body, footer):
    """Le message entier, ou coupé par la fin du détail sous MAX_MESSAGE octets."""
    lines = list(body)
    while True:
        cut = len(body) - len(lines)
        tail = [f"… {cut} ligne(s) coupée(s), le détail dans journalctl -u cost-report"] if cut else []
        message = "\n".join(head + [""] + lines + tail + [""] + footer)
        if len(message.encode()) <= MAX_MESSAGE or not lines:
            return message
        lines.pop()


def homepage_summary(results, now):
    """L'objet plat de la carte Coûts (apps-summary, /costs.json)."""
    missing = incomplete(results)
    last = previous_month(now.date())
    return {
        "previous_label": month_label(last),
        "previous_total": money_total(totals(results, "previous")),
        "current_total": money_total(totals(results, "current")),
        "missing": len(missing),
        "incomplete": ", ".join(f"{entry['name']} ({entry['status']})" for entry in missing) or "aucune",
        "updated": now.strftime("%d/%m %H:%M"),
    }


# --- Sorties -------------------------------------------------------------


def write_json(path, payload):
    """Écrit puis renomme : la carte ne lit jamais un fichier à moitié écrit."""
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.chmod(0o644)
    temporary.replace(path)


def read_state(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, ValueError):
        return {}


def due(state, now):
    """Le rapport du mois dernier n'est pas encore parti."""
    return state.get("published", "") < month_key(previous_month(now.date()))


def publish(url, topic, token, title, message, priority):
    body = json.dumps({"topic": topic, "title": title, "message": message, "priority": priority,
                       "tags": ["moneybag"]}).encode()
    request = urllib.request.Request(  # NOSONAR
        url.rstrip("/") + "/",
        data=body,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:  # noqa: S310 # NOSONAR
        response.read()


def load_config(path):
    config = json.loads(Path(path).read_text(encoding="utf-8"))
    for entry in config.get("subscriptions") or []:
        if entry.get("period") not in PERIODS or not entry.get("name") or not entry.get("currency"):
            raise ValueError(f"abonnement invalide : {entry.get('name')!r}")
        float(entry["amount"])
    return config


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--config", required=True, help="configuration JSON (rendue par Ansible)")
    parser.add_argument("--state-dir", required=True, help="dossier de costs.json et state.json")
    parser.add_argument("--publish", choices=("auto", "always", "never"), default="auto",
                        help="auto : une fois par mois ; always : maintenant ; never : jamais")
    parser.add_argument("--now", help="date et heure locales ISO (tests)")
    args = parser.parse_args(argv)

    now = datetime.datetime.fromisoformat(args.now) if args.now else datetime.datetime.now()
    config = load_config(args.config)
    state_dir = Path(args.state_dir)
    results = collect(config, os.environ, now)

    write_json(state_dir / "costs.json", homepage_summary(results, now))
    title, message, priority = build_report(results, now)
    print(f"{title}\n{message}")
    for entry in results:
        if entry["status"] == FAILED:
            print(f"{entry['name']} : {entry['note']}", file=sys.stderr)

    state_path = state_dir / "state.json"
    state = read_state(state_path)
    if args.publish == "never" or (args.publish == "auto" and not due(state, now)):
        return 0
    token = os.environ.get(NTFY_TOKEN, "")
    if not token:
        print(f"{NTFY_TOKEN} vide : rapport au journal seulement, rien n'est publié.", file=sys.stderr)
        return 0
    try:
        publish(config["ntfy_url"], config["ntfy_topic"], token, title, message, priority)
    except (OSError, http.client.HTTPException, ValueError) as error:
        # Sa classe seule : une erreur d'urllib peut citer la requête.
        print(f"publication sur ntfy en échec : {type(error).__name__}", file=sys.stderr)
        return 1
    write_json(state_path, {"published": month_key(previous_month(now.date()))})
    return 0


if __name__ == "__main__":
    sys.exit(main())
