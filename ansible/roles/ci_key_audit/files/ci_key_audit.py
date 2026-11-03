#!/usr/bin/env python3
"""Compare les connexions de la clé SSH de la CI aux runs GitHub du déploiement.

Rôle ci_key_audit, VM docker, bibliothèque standard seule. Une connexion hors
de tout run alerte ; un contrôle qui n'a pas pu conclure ne pousse aucun « up »
au moniteur Uptime Kuma, qui finit par tomber. README du rôle pour le pourquoi.
"""

import base64
import datetime
import hashlib
import http.client
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

CONFIG_FILE = "/etc/ci-key-audit/config.json"
PER_PAGE = 100
# VictoriaLogs ne garde que 30 jours : un curseur plus vieux ne lirait rien de plus.
MAX_WINDOW_SECONDS = 29 * 86400
# La ligne « clé connue » de la même session est déjà au journal, écrite avant.
COMPANION_LINE = "échec de la trace ntfy"
RUNBOOK = "docs/runbooks/perte-cle-ou-poste.md"
GAP_REPEAT_SECONDS = 86400
MAX_JOB_CHECKS = 10
MAX_ALERT_LINES = 20


class CheckError(Exception):
    """Le contrôle n'a pas pu conclure. Le message ne cite ni URL ni jeton."""


def fetch(label, url, headers=None, data=None, delays=(), sleep=time.sleep):
    """Corps de la réponse. Réessaie sur le réseau et les 5xx, jamais sur un 4xx."""
    request = urllib.request.Request(url, data=data, headers=headers or {})  # NOSONAR
    attempts = [*delays, None]
    for delay in attempts:
        try:
            with urllib.request.urlopen(request, timeout=30) as response:  # NOSONAR
                return response.read()
        except urllib.error.HTTPError as error:
            reason = f"HTTP {error.code}"
            if error.headers.get("X-RateLimit-Remaining") == "0":
                reset = error.headers.get("X-RateLimit-Reset", "?")
                raise CheckError(f"{label} : quota épuisé, retour à {reset}") from error
            if error.code < 500:
                raise CheckError(f"{label} : {reason}") from error
        except (OSError, http.client.HTTPException) as error:
            # Une erreur d'urllib peut citer l'URL : sa classe seule.
            reason = type(error).__name__
        if delay is None:
            raise CheckError(f"{label} : {reason}")
        sleep(delay)
    raise AssertionError("inaccessible")


def parse_time(value):
    """Epoch d'une date RFC 3339 ; VictoriaLogs donne jusqu'aux nanosecondes."""
    trimmed = re.sub(r"(\.\d{6})\d+", r"\1", value)
    return datetime.datetime.fromisoformat(trimmed.replace("Z", "+00:00")).timestamp()


def rfc3339(epoch):
    moment = datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc)
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


def clean(text, limit=300):
    """Une ligne de journal est à qui a la session : sans contrôle, et bornée."""
    return re.sub(r"[\x00-\x1f\x7f-\x9f]", " ", text)[:limit]


class Checker:
    def __init__(self, config, secrets, now, sleep=time.sleep):
        self.config = config
        self.secrets = secrets
        self.now = now
        self.sleep = sleep
        self.delays = tuple(config.get("retry_delays", (5, 20)))

    def logs_query(self, query, start, limit=None):
        params = {"query": query, "start": rfc3339(start), "end": rfc3339(self.now + 60)}
        if limit:
            params["limit"] = limit
        credentials = f"{self.config['vl_user']}:{self.secrets['vl_password']}".encode()
        token = base64.b64encode(credentials).decode()
        body = fetch(
            "VictoriaLogs",
            self.config["vl_url"].rstrip("/") + "/select/logsql/query",
            headers={"Authorization": f"Basic {token}"},
            data=urllib.parse.urlencode(params).encode(),
            delays=self.delays,
            sleep=self.sleep,
        )
        try:
            return [json.loads(line) for line in body.splitlines() if line.strip()]
        except ValueError as error:
            raise CheckError("VictoriaLogs : réponse illisible") from error

    def login_lines(self, start):
        """Toutes les lignes du hook de la fenêtre. Tronquées, elles ne prouvent rien."""
        limit = self.config["max_lines"]
        lines = self.logs_query(
            'identifier:="ssh-login-notify" source:=journald | fields _time, host, _msg', start, limit
        )
        if len(lines) >= limit:
            raise CheckError(f"VictoriaLogs : au moins {limit} lignes, fenêtre tronquée")
        return lines

    def fresh_hosts(self):
        """Hôtes dont le journal arrive : le canal des lignes du hook, hook ou pas."""
        start = self.now - self.config["freshness_seconds"]
        rows = self.logs_query('{source="journald"} | stats by (host) count() as n', start)
        return {row.get("host") for row in rows}

    def github(self, path, query=None):
        url = self.config["github_api"].rstrip("/") + path
        if query:
            url += "?" + urllib.parse.urlencode(query)
        headers = {
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "ci-key-audit",
        }
        body = fetch("GitHub", url, headers=headers, delays=self.delays, sleep=self.sleep)
        try:
            return json.loads(body)
        except ValueError as error:
            raise CheckError("GitHub : réponse illisible") from error

    def repo_path(self):
        return f"/repos/{self.config['repository']}/actions"

    def runs(self, since):
        """Les runs du déploiement créés depuis `since`, page après page."""
        path = f"{self.repo_path()}/workflows/{self.config['workflow']}/runs"
        found = []
        for page in range(1, self.config["max_pages"] + 1):
            batch = self.github(path, {
                "created": ">=" + rfc3339(since),
                "branch": self.config["branch"],
                "exclude_pull_requests": "true",
                "per_page": PER_PAGE,
                "page": page,
            })["workflow_runs"]
            found.extend(batch)
            if len(batch) < PER_PAGE:
                return found
        raise CheckError(f"GitHub : plus de {self.config['max_pages']} pages de runs")

    def earlier_attempts(self, run):
        """Un run relancé ne montre que son dernier essai ; les connexions du premier comptent."""
        attempts = []
        for attempt in range(1, run.get("run_attempt", 1)):
            attempts.append(self.github(f"{self.repo_path()}/runs/{run['id']}/attempts/{attempt}"))
        return attempts

    def deployed_hosts(self, run):
        """Hôtes dont l'étape « Deploy <hôte> » a réussi : ils ont vu la clé."""
        attempt = run.get("run_attempt", 1)
        jobs = self.github(
            f"{self.repo_path()}/runs/{run['id']}/attempts/{attempt}/jobs", {"per_page": PER_PAGE}
        )["jobs"]
        steps = {
            step.get("name"): step.get("conclusion")
            for job in jobs
            for step in job.get("steps", [])
        }
        return [host for host in self.config["hosts"] if steps.get(f"Deploy {host}") == "success"]

    def run_interval(self, run):
        """[début, fin] d'un run ; encore ouvert à maintenant s'il n'est pas fini."""
        start = parse_time(run.get("run_started_at") or run["created_at"])
        end = parse_time(run["updated_at"]) if run.get("status") == "completed" else self.now
        return start, end

    def covered(self, moment, intervals):
        margin = self.config["margin_seconds"]
        return any(start - margin <= moment <= end + margin for start, end in intervals)

    def publish(self, title, message, priority):
        body = json.dumps({
            "topic": self.config["ntfy_topic"],
            "title": title,
            "message": message,
            "priority": priority,
            "tags": ["rotating_light"],
        }).encode()
        fetch(
            "ntfy",
            self.config["ntfy_url"].rstrip("/") + "/",
            headers={
                "Authorization": f"Bearer {self.secrets['ntfy_token']}",
                "Content-Type": "application/json",
            },
            data=body,
            delays=self.delays,
            sleep=self.sleep,
        )

    def push(self, status, message):
        """Par uptime-push : l'URL (jeton du moniteur) sur stdin, jamais sur la ligne de commande."""
        url = self.secrets.get("push_url", "")
        if not url:
            print("URL push vide (moniteur pas appliqué) : rien n'est poussé.", file=sys.stderr)
            return True
        result = subprocess.run(  # NOSONAR
            [self.config["uptime_push_bin"], "--strict", "--agent", "ci-key-audit", "-", status, clean(message, 250)],
            input=f'url = "{url}"\n',
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            print(f"push {status} en échec (curl {result.returncode})", file=sys.stderr)
        return result.returncode == 0


def event_id(line):
    raw = "\0".join((line["host"], line["_time"], line["_msg"]))
    return hashlib.sha256(raw.encode()).hexdigest()[:24]


def load_state(path):
    try:
        with open(path, encoding="utf-8") as file:
            state = json.load(file)
        if isinstance(state, dict):
            return state
        print("état illisible : on repart de la fenêtre initiale", file=sys.stderr)
    except FileNotFoundError:
        pass
    except ValueError:
        # Revoir une alerte plutôt qu'en perdre une.
        print("état illisible : on repart de la fenêtre initiale", file=sys.stderr)
    return {}


def save_state(path, state):
    directory = os.path.dirname(path) or "."
    with tempfile.NamedTemporaryFile("w", dir=directory, delete=False, encoding="utf-8") as file:
        json.dump(state, file)
    os.replace(file.name, path)


def describe(line):
    moment = rfc3339(parse_time(line["_time"]))
    return f"{clean(line['host'], 40)} {moment} : {clean(line['_msg'])}"


def bounded(lines):
    shown = lines[:MAX_ALERT_LINES]
    hidden = len(lines) - len(shown)
    return "\n".join(shown + ([f"… et {hidden} de plus"] if hidden > 0 else []))


def tick(checker, state):
    """Un passage. Modifie `state` ; rend le résumé, les alertes parties, les manques."""
    config = checker.config
    now = checker.now
    overlap = config["overlap_seconds"]
    fingerprint = config["fingerprint"]

    installed_at = state.setdefault("installed_at", now)
    # Curseur persisté, moins un recouvrement : un passage manqué, une panne de
    # plusieurs jours ou une ligne en retard retombent dans la fenêtre suivante.
    cursor = state.get("cursor", now - config["initial_lookback_seconds"] + overlap)
    start = max(cursor - overlap, now - MAX_WINDOW_SECONDS)
    seen = state.setdefault("seen", {})
    checked_runs = state.setdefault("checked_runs", {})
    gap_notified = state.setdefault("gap_notified", {})

    # Une panne ici ne touche à rien de l'état : le passage suivant relit tout.
    lines = checker.login_lines(start)
    fresh = checker.fresh_hosts()
    runs = checker.runs(start - config["run_lookback_seconds"])

    ci_lines = [
        line for line in lines
        if fingerprint in line["_msg"] and not line["_msg"].startswith(COMPANION_LINE)
    ]
    judged = [line for line in ci_lines if line["host"] not in config["excluded_hosts"]]
    judged.sort(key=lambda line: parse_time(line["_time"]))
    intervals = [checker.run_interval(run) for run in runs]

    pending = []
    for line in judged:
        identifier = event_id(line)
        if identifier in seen:
            continue
        moment = parse_time(line["_time"])
        if checker.covered(moment, intervals):
            seen[identifier] = moment
        else:
            pending.append((identifier, moment, line))
    if pending:
        for run in runs:
            intervals.extend(checker.run_interval(attempt) for attempt in checker.earlier_attempts(run))

    anomalies = []
    for identifier, moment, line in pending:
        if checker.covered(moment, intervals):
            seen[identifier] = moment
        elif now - moment >= config["settle_seconds"]:
            # Plus jeune : le run peut ne pas être encore visible dans l'API ;
            # le recouvrement, plus long que cette attente, la relira.
            anomalies.append((identifier, moment, line))

    # Une étape « Deploy <hôte> » réussie sans aucune ligne du hook : hook absent
    # ou format changé, le contrôle est aveugle sur cet hôte.
    gaps = []
    done_runs = []
    to_check = [
        run for run in runs
        if run.get("status") == "completed"
        and f"{run['id']}:{run.get('run_attempt', 1)}" not in checked_runs
        and checker.run_interval(run)[0] >= max(start, installed_at)
        and checker.run_interval(run)[1] <= now - config["settle_seconds"]
    ]
    for run in sorted(to_check, key=lambda item: item["updated_at"])[:MAX_JOB_CHECKS]:
        interval = checker.run_interval(run)
        complete = True
        for host in checker.deployed_hosts(run):
            if host not in fresh:
                complete = False  # ses lignes sont peut-être en route : plus tard
            elif not any(
                line["host"] == host and checker.covered(parse_time(line["_time"]), [interval])
                for line in ci_lines
            ):
                gaps.append((host, run["id"]))
        if complete:
            done_runs.append((f"{run['id']}:{run.get('run_attempt', 1)}", interval[1]))

    errors = []
    published = []
    if anomalies:
        text = bounded([describe(line) for _, _, line in anomalies])
        try:
            checker.publish(
                "Clé de CI utilisée hors déploiement",
                f"{text}\nConnexion hors de tout run de {config['workflow']}. Clé volée ? {RUNBOOK}",
                5,
            )
        except CheckError as error:
            errors.append(str(error))
        else:
            seen.update({identifier: moment for identifier, moment, _ in anomalies})
        published.append(f"{len(anomalies)} connexion(s) de la clé de CI hors run : {describe(anomalies[0][2])}")

    new_gaps = sorted({host for host, _ in gaps if now - gap_notified.get(host, 0) >= GAP_REPEAT_SECONDS})
    gap_ok = True
    if new_gaps:
        try:
            checker.publish(
                "Contrôle de la clé de CI aveugle",
                f"Déploiement réussi sans ligne ssh-login-notify sur : {', '.join(new_gaps)}. "
                "Hook absent ou format changé (README de ci_key_audit).",
                4,
            )
        except CheckError as error:
            errors.append(str(error))
            gap_ok = False
        else:
            gap_notified.update({host: now for host in new_gaps})
        published.append(f"Déploiement sans ligne ssh-login-notify sur {', '.join(new_gaps)}")
    if gap_ok:
        checked_runs.update(dict(done_runs))

    stale = sorted(set(config["hosts"]) - fresh)
    if stale:
        errors.append(f"journal silencieux depuis {config['freshness_seconds']} s : {', '.join(stale)}")

    # Le curseur n'avance que sur un passage complet : une panne se relit au retour.
    new_cursor = now if not errors else cursor
    state["cursor"] = new_cursor
    next_start = new_cursor - overlap
    state["seen"] = {key: moment for key, moment in seen.items() if moment >= next_start}
    state["checked_runs"] = {key: moment for key, moment in checked_runs.items() if moment >= next_start}

    summary = f"{len(lines)} ligne(s) du hook, {len(judged)} de la clé de CI, {len(runs)} run(s)"
    return summary, published, errors


def main():
    with open(CONFIG_FILE, encoding="utf-8") as file:
        config = json.load(file)
    with open(os.path.join(os.environ["CREDENTIALS_DIRECTORY"], "secrets.json"), encoding="utf-8") as file:
        secrets = json.load(file)
    state_path = os.path.join(os.environ["STATE_DIRECTORY"], "state.json")
    checker = Checker(config, secrets, time.time())
    state = load_state(state_path)

    try:
        summary, published, errors = tick(checker, state)
    except CheckError as error:
        # Aucun push : le moniteur tombe à l'expiration de son intervalle.
        print(f"contrôle impossible : {error}", file=sys.stderr)
        return 1
    save_state(state_path, state)

    print(summary)
    for error in errors:
        print(f"contrôle incomplet : {error}", file=sys.stderr)
    # Un moniteur déjà DOWN ne renotifie pas : ntfy porte chaque alerte, ce down
    # double sur Telegram (et dit l'alerte si ntfy est tombé).
    if published:
        print("\n".join(published), file=sys.stderr)
        return 1 if not checker.push("down", published[0]) or errors else 0
    if errors:
        return 1
    return 0 if checker.push("up", summary) else 1


if __name__ == "__main__":
    sys.exit(main())
