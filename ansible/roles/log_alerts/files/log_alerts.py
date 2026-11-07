#!/usr/bin/python3
"""Alertes sur les journaux VictoriaLogs (rôle log_alerts).

Chaque règle est une requête LogsQL qui finit par `stats by (...) count() n`,
rejouée sur une fenêtre glissante : une alerte ntfy par groupe dont le compte
atteint le seuil, ou, avec `expect_hosts`, par hôte attendu qui n'a écrit aucune
ligne (absence). Une alerte n'est répétée qu'après `repeat_seconds`. Le moniteur
push d'Uptime Kuma ne reçoit `up` que si toutes les règles ont pu être jugées et
ses alertes livrées : sans battement, le contrôle est aveugle et le moniteur tombe.
"""
import base64
import datetime
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

CONFIG_FILE = os.environ.get("LOG_ALERTS_CONFIG", "/etc/log-alerts/config.json")
# Sans pièces jointes (rôle ntfy), ntfy refuse en 400 un message de plus de 4 096 octets.
MAX_ALERT_LINES = 20


class CheckError(Exception):
    """Le contrôle n'a pas pu conclure. Le message ne cite ni URL ni jeton."""


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


# Les requêtes portent un secret : aucune redirection, une 3xx est une erreur.
_OPENER = urllib.request.build_opener(_NoRedirect)


def post(label, url, headers, data):
    request = urllib.request.Request(url, data=data, headers=headers)  # NOSONAR
    try:
        with _OPENER.open(request, timeout=30) as response:  # NOSONAR
            return response.read()
    except urllib.error.HTTPError as error:
        raise CheckError(f"{label} : HTTP {error.code}") from error
    except (OSError, ValueError) as error:
        # Une erreur d'urllib peut citer l'URL : sa classe seule.
        raise CheckError(f"{label} : {type(error).__name__}") from None


def clean(text, limit=200):
    """Une valeur de journal est à qui l'a écrite : sans contrôle, et bornée."""
    return re.sub(r"[\x00-\x1f\x7f-\x9f]", " ", str(text))[:limit]


def rfc3339(epoch):
    return datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def query_rows(config, secrets, rule, now):
    credentials = f"{config['vl_user']}:{secrets['vl_password']}".encode()
    params = {"query": rule["query"], "start": rfc3339(now - rule["window_seconds"])}
    body = post(
        "VictoriaLogs",
        config["vl_url"].rstrip("/") + "/select/logsql/query",
        {"Authorization": "Basic " + base64.b64encode(credentials).decode()},
        urllib.parse.urlencode(params).encode(),
    )
    try:
        return [json.loads(line) for line in body.splitlines() if line.strip()]
    except ValueError as error:
        raise CheckError("VictoriaLogs : réponse illisible") from error


def judge(rule, rows):
    """[(groupe, détail)] des alertes de la règle."""
    if rule.get("expect_hosts"):
        seen = {row.get("host") for row in rows}
        hours = rule["window_seconds"] // 3600
        return [(host, f"aucune ligne en {hours} h") for host in rule["expect_hosts"] if host not in seen]
    found = []
    for row in rows:
        count = int(row["n"])
        if count >= rule["threshold"]:
            group = ", ".join(clean(value) for key, value in sorted(row.items()) if key != "n" and value)
            found.append((group or "-", f"{count} en {rule['window_seconds'] // 60} min"))
    return found


def publish(config, secrets, rule, lines):
    body = json.dumps({
        "topic": config["ntfy_topic"],
        "title": rule["title"],
        "message": "\n".join(lines[:MAX_ALERT_LINES]),
        "priority": rule["priority"],
        "tags": ["rotating_light"],
    }).encode()
    post(
        "ntfy",
        config["ntfy_url"].rstrip("/") + "/",
        {"Authorization": f"Bearer {secrets['ntfy_token']}", "Content-Type": "application/json"},
        body,
    )


def push(config, secrets, message):
    """Par uptime-push : l'URL (jeton du moniteur) sur stdin, jamais sur la ligne de commande."""
    if not secrets["push_url"]:
        print("URL push vide (moniteur pas appliqué) : rien n'est poussé.", file=sys.stderr)
        return True
    result = subprocess.run(  # NOSONAR
        [config["uptime_push_bin"], "--strict", "--agent", "log-alerts", "-", "up", message],
        input=f'url = "{secrets["push_url"]}"\n',
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        print(f"push en échec (uptime-push {result.returncode})", file=sys.stderr)
    return result.returncode == 0


def load_state(path):
    try:
        with open(path, encoding="utf-8") as file:
            state = json.load(file)
        return state if isinstance(state, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(path, state):
    with open(path + ".tmp", "w", encoding="utf-8") as file:
        json.dump(state, file)
    os.replace(path + ".tmp", path)


def run(config, secrets, state, now):
    """(nombre d'alertes livrées, erreurs). `state` : « règle|groupe » -> dernière alerte."""
    delivered, errors = 0, []
    for rule in config["rules"]:
        try:
            alerts = judge(rule, query_rows(config, secrets, rule, now))
            fresh = [(group, detail) for group, detail in alerts
                     if now - state.get(f"{rule['name']}|{group}", 0) >= rule["repeat_seconds"]]
            if fresh:
                publish(config, secrets, rule, [f"{group} : {detail}" for group, detail in fresh])
                for group, _ in fresh:
                    state[f"{rule['name']}|{group}"] = now
                delivered += len(fresh)
        except CheckError as error:
            errors.append(f"{rule['name']} : {error}")
    # Un groupe qui ne sonne plus depuis deux fois sa répétition est oublié.
    longest = max((rule["repeat_seconds"] for rule in config["rules"]), default=0)
    for key in [k for k, moment in state.items() if now - moment > 2 * longest]:
        del state[key]
    return delivered, errors


def main():
    with open(CONFIG_FILE, encoding="utf-8") as file:
        config = json.load(file)
    # Retirés de l'environnement : uptime-push et curl n'en héritent pas.
    secrets = {
        "vl_password": os.environ.pop("LOG_ALERTS_VL_PASSWORD"),
        "ntfy_token": os.environ.pop("LOG_ALERTS_NTFY_TOKEN"),
        "push_url": os.environ.pop("LOG_ALERTS_PUSH_URL", ""),
    }
    state_path = os.path.join(os.environ["STATE_DIRECTORY"], "state.json")
    state = load_state(state_path)
    delivered, errors = run(config, secrets, state, time.time())
    save_state(state_path, state)
    for error in errors:
        print(f"contrôle incomplet : {error}", file=sys.stderr)
    if errors:
        # Aucun push : le moniteur tombe à l'expiration de son intervalle.
        return 1
    summary = f"{len(config['rules'])} règles jugées, {delivered} alerte(s) envoyée(s)"
    print(summary)
    return 0 if push(config, secrets, summary) else 1


if __name__ == "__main__":
    sys.exit(main())
