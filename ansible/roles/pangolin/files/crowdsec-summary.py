#!/usr/bin/python3
"""Résumé quotidien de CrowdSec sur ntfy (rôle pangolin, crowdsec-summary.timer).

Lit les alertes locales des dernières 24 h (`cscli alerts list --since 24h`,
liste communautaire exclue) et publie un court résumé sur ntfy : alertes par
scénario et par pays, bannissements, correspondances AppSec en détection
seule (scénario homelab/appsec-alert-only). Priorité basse, haute quand un
scénario s'emballe (au moins SPIKE_MIN alertes et SPIKE_FACTOR fois sa
moyenne des jours précédents) ou qu'AppSec voit une règle jamais vue. Un
cscli injoignable publie aussi, en priorité haute, et le service échoue.

L'historique (comptes par scénario des derniers jours, règles AppSec déjà
vues) est dans CROWDSEC_SUMMARY_STATE, écrit après une publication réussie
seulement. Premier passage sans historique : aucun pic ni règle nouvelle.

Environnement (EnvironmentFile 0600 de l'unité) : NTFY_URL, NTFY_TOPIC,
NTFY_TOKEN (jamais affiché ni passé en argument). CROWDSEC_SUMMARY_CSCLI
remplace `docker exec crowdsec cscli` (Molecule : un faux cscli).

    crowdsec-summary [--dry-run]   # --dry-run : affiche la charge, ne publie
                                   # rien, n'écrit pas l'historique
"""

import argparse
import http.client
import json
import os
import shlex
import subprocess
import sys
import urllib.error
import urllib.request
from collections import Counter
from pathlib import Path

DEFAULT_CSCLI = "docker exec crowdsec cscli"
DEFAULT_STATE = "/var/lib/crowdsec-summary/state.json"
APPSEC_SCENARIOS = ("homelab/appsec-alert-only", "crowdsecurity/appsec-generic-test")
HISTORY_DAYS = 7
SPIKE_MIN = 10
SPIKE_FACTOR = 3
TOP = 8
PRIORITY_LOW = 2
PRIORITY_HIGH = 4


class CscliError(Exception):
    """cscli injoignable ou réponse illisible."""


def cscli_alerts(command):
    """Alertes locales des dernières 24 h, toutes (--limit 0)."""
    args = shlex.split(command) + ["alerts", "list", "--since", "24h", "--limit", "0", "-o", "json"]
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=120, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise CscliError(f"cscli injoignable : {type(error).__name__}") from error
    if result.returncode != 0:
        tail = result.stderr.strip().splitlines()[-1:] or [""]
        raise CscliError(f"cscli a échoué (code {result.returncode}) : {tail[0][:200]}")
    try:
        alerts = json.loads(result.stdout or "null")
    except ValueError as error:
        raise CscliError("cscli : JSON illisible") from error
    if alerts is None:
        return []
    if not isinstance(alerts, list):
        raise CscliError("cscli : une liste d'alertes était attendue")
    return alerts


def appsec_rules(alert):
    """Règles AppSec d'une alerte (meta rule_name de ses événements)."""
    rules = set()
    for event in alert.get("events") or []:
        for meta in event.get("meta") or []:
            if meta.get("key") == "rule_name" and meta.get("value"):
                rules.add(meta["value"])
    # Sans meta rule_name, aucune règle : une « règle nouvelle » inventée
    # serait une fausse alerte en priorité haute.
    return rules


def summarize(alerts):
    """Comptes de la journée : scénarios, pays, bannissements, AppSec."""
    scenarios, countries = Counter(), Counter()
    banned, appsec_ips, rules = set(), set(), set()
    bans = appsec = 0
    for alert in alerts:
        scenario = alert.get("scenario") or "?"
        source = alert.get("source") or {}
        ip = source.get("ip") or source.get("value") or "?"
        if scenario in APPSEC_SCENARIOS:
            appsec += 1
            appsec_ips.add(ip)
            rules |= appsec_rules(alert)
            continue
        scenarios[scenario] += 1
        countries[source.get("cn") or "??"] += 1
        for decision in alert.get("decisions") or []:
            if decision.get("type") == "ban":
                bans += 1
                banned.add(decision.get("value") or ip)
    return {
        "scenarios": scenarios,
        "countries": countries,
        "bans": bans,
        "banned_ips": len(banned),
        "appsec": appsec,
        "appsec_ips": len(appsec_ips),
        "rules": rules,
    }


def load_state(path):
    try:
        state = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if not isinstance(state, dict):
        return None
    history, rules = state.get("history", []), state.get("rules", [])
    if not isinstance(history, list) or not isinstance(rules, list):
        return None
    # Un historique abîmé ne doit pas faire planter le résumé : seuls les
    # comptes entiers sont gardés.
    days = [
        {scenario: count for scenario, count in day.items() if isinstance(count, int)}
        for day in history
        if isinstance(day, dict)
    ]
    return {
        "history": days[-HISTORY_DAYS:],
        "rules": [rule for rule in rules if isinstance(rule, str)],
    }


def save_state(path, state, today):
    history = (state["history"] if state else []) + [dict(today["scenarios"])]
    rules = sorted(set(state["rules"] if state else []) | today["rules"])
    target = Path(path)
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    tmp = target.with_suffix(".tmp")
    tmp.write_text(json.dumps({"history": history[-HISTORY_DAYS:], "rules": rules}), encoding="utf-8")
    tmp.chmod(0o600)
    tmp.replace(target)


def spikes(today, state):
    """{scénario: moyenne précédente} des scénarios qui s'emballent."""
    if not state or not state["history"]:
        return {}
    days = state["history"]
    found = {}
    for scenario, count in today["scenarios"].items():
        mean = sum(day.get(scenario, 0) for day in days) / len(days)
        if count >= SPIKE_MIN and count >= SPIKE_FACTOR * mean:
            found[scenario] = mean
    return found


def new_rules(today, state):
    if not state:
        return set()
    return today["rules"] - set(state["rules"])


def plural(count, word):
    return f"{count} {word}{'s' if count > 1 else ''}"


def message(today, state, topic):
    spiking = spikes(today, state)
    fresh = new_rules(today, state)
    total = sum(today["scenarios"].values())
    lines = []
    if total:
        lines.append("Scénarios :")
        for scenario, count in today["scenarios"].most_common(TOP):
            note = f" (pic, moyenne {spiking[scenario]:.0f})" if scenario in spiking else ""
            lines.append(f"  {scenario} {count}{note}")
        rest = len(today["scenarios"]) - TOP
        if rest > 0:
            lines.append(f"  … et {plural(rest, 'autre')}")
        lines.append("Pays : " + ", ".join(f"{cn} {count}" for cn, count in today["countries"].most_common(TOP)))
        lines.append(f"Bannissements : {today['bans']} ({today['banned_ips']} IP)")
    if today["appsec"]:
        lines.append(
            f"AppSec (détection seule) : {plural(today['appsec'], 'alerte')}, {today['appsec_ips']} IP"
        )
        if fresh:
            lines.append("  Règles nouvelles : " + ", ".join(sorted(fresh)))
    if not lines:
        lines.append("Aucune alerte locale en 24 h.")
    high = bool(spiking or fresh)
    title = f"CrowdSec 24 h : {plural(total, 'alerte')}, {plural(today['bans'], 'bannissement')}"
    if today["appsec"]:
        title += f", AppSec {today['appsec']}"
    return {
        "topic": topic,
        "title": title,
        "message": "\n".join(lines),
        "priority": PRIORITY_HIGH if high else PRIORITY_LOW,
        "tags": ["warning", "shield"] if high else ["shield"],
    }


def failure_message(error, topic):
    return {
        "topic": topic,
        "title": "CrowdSec : résumé impossible",
        "message": f"{error}\nsudo docker ps --filter name=crowdsec ; docs/runbooks/crowdsec.md",
        "priority": PRIORITY_HIGH,
        "tags": ["warning", "shield"],
    }


def publish(url, token, payload):
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        response.read()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true", help="affiche la charge sans la publier")
    args = parser.parse_args(argv)

    url = os.environ.get("NTFY_URL", "")
    topic = os.environ.get("NTFY_TOPIC", "")
    token = os.environ.get("NTFY_TOKEN", "")
    state_path = os.environ.get("CROWDSEC_SUMMARY_STATE", DEFAULT_STATE)
    cscli = os.environ.get("CROWDSEC_SUMMARY_CSCLI", DEFAULT_CSCLI)

    failed = False
    today = state = None
    try:
        alerts = cscli_alerts(cscli)
        today = summarize(alerts)
        state = load_state(state_path)
        payload = message(today, state, topic)
    except CscliError as error:
        failed = True
        payload = failure_message(error, topic)

    if args.dry_run:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 1 if failed else 0

    if not (url and topic and token):
        print("NTFY_URL, NTFY_TOPIC ou NTFY_TOKEN vide : rien n'est publié.", file=sys.stderr)
        return 1
    try:
        publish(url, token, payload)
    except urllib.error.HTTPError as error:
        print(f"publication ntfy en échec : HTTP {error.code}", file=sys.stderr)
        return 1
    except (OSError, ValueError, http.client.HTTPException) as error:
        # Sa classe seule : le message d'une erreur réseau peut citer la requête.
        print(f"publication ntfy en échec : {type(error).__name__}", file=sys.stderr)
        return 1
    print(payload["title"])
    if failed:
        return 1
    save_state(state_path, state, today)
    return 0


if __name__ == "__main__":
    sys.exit(main())
