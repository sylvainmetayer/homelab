#!/usr/bin/env python3
"""Compteurs de Blocky pour la carte Blocky de Homepage (rôle blocky).

Lancé par blocky-check.service avant la vérification : lit les compteurs
Prometheus de Blocky sur la boucle locale (le port HTTP de Blocky sert aussi
une API sans authentification, il ne quitte jamais 127.0.0.1) et écrit une
ligne logfmt au journal, que l'agent de journaux (rôle log_agent) envoie à
VictoriaLogs :

    event=blocky_stats queries=42 blocked=7 queries_total=1234 blocked_total=99

queries et blocked sont les requêtes et les blocages depuis la ligne
précédente : la carte en fait la somme sur 24 h (stats_query de vmauth). Les
compteurs de Blocky repartent de zéro à chaque redémarrage ; le delta est
calculé ici, contre les totaux du passage précédent gardés dans
STATE_DIRECTORY : un redémarrage (heure de démarrage du processus avancée de
plus de START_JITTER, ou compteur plus bas que la dernière fois) compte le
total depuis le redémarrage, pas une différence négative. Un passage manqué
(Blocky arrêté, métriques illisibles) ne perd rien : le suivant compte depuis
le dernier relevé réussi. Au tout premier passage, rien à comparer : 0. État
non écrit : pas de ligne (sinon le passage suivant recompterait ce delta).

Bibliothèque standard seulement. Ne fait jamais échouer l'unité : une erreur
est écrite sur stderr et le script sort en 0 (la vérification qui suit
reste seule juge de l'état de Blocky).
"""

import json
import math
import os
import sys
import urllib.request

QUERY_METRIC = "blocky_query_total"
RESPONSE_METRIC = "blocky_response_total"
BLOCKED_LABEL = 'response_type="BLOCKED"'
START_METRIC = "process_start_time_seconds"
# process_start_time_seconds = btime de /proc/stat (secondes entières,
# relu à chaque lecture) + démarrage depuis le boot : quand NTP ajuste
# l'horloge, btime bouge d'une seconde sans redémarrage. Un vrai redémarrage
# suit le relevé précédent, donc avance l'heure de démarrage de bien plus.
START_JITTER = 2.0
MAX_BYTES = 4 * 1024 * 1024
STATE_FILE = "counters.json"


def parse(text):
    """Totaux (requêtes, blocages) et heure de démarrage du processus."""
    queries = 0.0
    blocked = 0.0
    start = None
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        # « nom{labels} valeur [horodatage] » ; une valeur de label peut
        # contenir des espaces (reason="BLOCKED (ads)") : les labels vont
        # jusqu'à la dernière accolade, la valeur suit.
        if "{" in line:
            name, _, rest = line.partition("{")
            labels, _, rest = rest.rpartition("}")
        else:
            name, _, rest = line.partition(" ")
            labels = ""
        parts = rest.split()
        if not parts:
            continue
        name = name.strip()
        try:
            value = float(parts[0])
        except ValueError:
            continue
        if not math.isfinite(value):
            continue
        if name == QUERY_METRIC:
            queries += value
        elif name == RESPONSE_METRIC and BLOCKED_LABEL in labels:
            blocked += value
        elif name == START_METRIC:
            start = value
    return queries, blocked, start


def delta(current, previous, restarted):
    """Ce qui s'est passé depuis le relevé précédent."""
    if previous is None:
        return 0
    if restarted or current < previous:
        return current
    return current - previous


def compute(totals, state):
    """(ligne logfmt, nouvel état) à partir des totaux et de l'état gardé."""
    queries, blocked, start = totals
    previous_start = state.get("start")
    restarted = (
        isinstance(start, float)
        and isinstance(previous_start, (int, float))
        and start - previous_start > START_JITTER
    )
    # load_state rend {} ou les deux totaux : sans état, None, donc 0.
    d_queries = delta(queries, state.get("queries"), restarted)
    d_blocked = delta(blocked, state.get("blocked"), restarted)
    line = (
        f"event=blocky_stats queries={d_queries:.0f} blocked={d_blocked:.0f}"
        f" queries_total={queries:.0f} blocked_total={blocked:.0f}"
    )
    return line, {"queries": queries, "blocked": blocked, "start": start}


def fetch(url):
    # Pas de proxy : l'adresse est locale.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(url, timeout=5) as response:
        body = response.read(MAX_BYTES + 1)
    if len(body) > MAX_BYTES:
        raise ValueError("métriques de plus de 4 Mio")
    return body.decode("utf-8", "replace")


def load_state(path):
    try:
        with open(path, encoding="utf-8") as handle:
            state = json.load(handle)
    except (OSError, ValueError):
        return {}
    if not isinstance(state, dict):
        return {}
    for key in ("queries", "blocked"):
        if not isinstance(state.get(key), (int, float)):
            return {}
    return state


def save_state(path, state):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(state, handle)
    os.replace(tmp, path)


def main(argv):
    if len(argv) != 2:
        print("usage: blocky_stats.py <url des métriques>", file=sys.stderr)
        return 0
    state_dir = os.environ.get("STATE_DIRECTORY", "")
    if not state_dir:
        print("blocky_stats : STATE_DIRECTORY absent", file=sys.stderr)
        return 0
    # STATE_DIRECTORY peut en lister plusieurs (« : ») : le premier.
    path = os.path.join(state_dir.split(":", 1)[0], STATE_FILE)
    try:
        totals = parse(fetch(argv[1]))
    except Exception as error:  # noqa: BLE001 — jamais d'échec de l'unité
        print(f"blocky_stats : métriques illisibles ({type(error).__name__})", file=sys.stderr)
        return 0
    line, state = compute(totals, load_state(path))
    # L'état d'abord : écrit sans lui, ce delta serait recompté au passage
    # suivant, et à chaque passage tant que l'état reste illisible.
    try:
        save_state(path, state)
    except OSError as error:
        print(f"blocky_stats : état non écrit ({error.strerror})", file=sys.stderr)
        return 0
    print(line, flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
