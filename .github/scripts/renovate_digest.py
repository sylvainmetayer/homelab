"""Bilan hebdomadaire de Renovate, publié sur ntfy (topic github).

Lu par .github/workflows/renovate-digest.yaml, le lundi après-midi, après le
passage du matin de Renovate (« before 9am on monday », renovate.json) et
les fusions automatiques qui le suivent. Sur les 7 derniers jours :
  - les PR de Renovate fusionnées, automatiquement (fusionnées par Renovate
    lui-même : automerge, platformAutomerge) puis à la main ; les montées
    répétées d'un même paquet (images maison, une par build) regroupées ;
  - les PR de Renovate encore ouvertes, avec leur âge, les plus vieilles
    d'abord ; celles dont l'auto-merge attend les checks sont signalées ;
  - les runs en échec de deploy-docker-app.yaml ; un échec suivi d'un run
    de push réussi est « rattrapé » (ce run redéploie tout depuis le
    dernier succès) et ne fait plus monter la priorité.

API GraphQL (une recherche pour les PR, avec mergedBy et autoMergeRequest)
et REST (runs du workflow), avec le GITHUB_TOKEN du job (lecture seule). Le
jeton ntfy (écriture seule sur le topic github) arrive par l'environnement,
jamais affiché. Une API en échec publie quand même un message, et le run
échoue : un bilan qui ne vient plus ne se remarque pas.
"""

import argparse
import datetime
import http.client
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter

API = "https://api.github.com"
# Limite de ntfy sans pièces jointes (4096 octets), marge pour le JSON.
MAX_MESSAGE = 3800
RENOVATE_LOGINS = {"renovate", "renovate[bot]", "app/renovate"}
DEPLOY_WORKFLOW = "deploy-docker-app.yaml"
# Constantes, pas des arguments : aucune entrée ne choisit où part le jeton.
NTFY_URL = "https://ntfy.sylvain.cloud"
NTFY_TOPIC = "github"

PULLS_QUERY = """
query($merged: String!, $open: String!) {
  merged: search(type: ISSUE, query: $merged, first: 100) {
    issueCount
    nodes { ... on PullRequest { number title url mergedAt mergedBy { login } } }
  }
  open: search(type: ISSUE, query: $open, first: 100) {
    issueCount
    nodes { ... on PullRequest { number title url createdAt isDraft autoMergeRequest { enabledAt } } }
  }
}
"""

# « chore(deps): update planning-equipes main (demo_planning) to 12d83c7 » :
# le paquet, sans la version cible ; le « [SECURITY] » que Renovate ajoute aux
# PR de vulnérabilité reste.
TITLE_PREFIX = re.compile(r"^(?:chore|fix|build|ci)\(deps\):\s*", re.IGNORECASE)
SECURITY_MARKER = " [SECURITY]"


class DigestError(Exception):
    """Réponse de l'API inexploitable."""


def parse_time(value):
    return datetime.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)


def short_title(title):
    return TITLE_PREFIX.sub("", title).strip()


def package(title):
    name = short_title(title)
    security = name.upper().endswith(SECURITY_MARKER)
    if security:
        name = name[: -len(SECURITY_MARKER)]
    head, separator, target = name.rpartition(" to ")
    if separator and target and " " not in target:
        name = head
    return name + (SECURITY_MARKER if security else "")


def grouped(pulls):
    """Une ligne par paquet, « xN » quand il est monté plusieurs fois."""
    counts = Counter(package(pull["title"]) for pull in pulls)
    lines = []
    for name, count in sorted(counts.items(), key=lambda item: (-item[1], item[0])):
        lines.append(f"- {name}" + (f" x{count}" if count > 1 else ""))
    return lines


def age(created, now):
    days = (now - parse_time(created)).total_seconds() / 86400
    return f"{days:.0f} j" if days >= 1 else "moins d'un jour"


def render(sections, footer, dropped=0):
    parts = [title + "\n" + "\n".join(lines) for title, lines in sections if lines]
    if dropped:
        parts.append(f"... et {dropped} ligne(s) de plus : résumé du run")
    return "\n\n".join(parts + [footer])


def fit(sections, footer):
    """Le message sous MAX_MESSAGE octets : les dernières lignes de la plus
    longue section partent les premières."""
    sections = [(title, list(lines)) for title, lines in sections if lines]
    dropped = 0
    message = render(sections, footer)
    while len(message.encode()) > MAX_MESSAGE and any(lines for _, lines in sections):
        max((lines for _, lines in sections), key=len).pop()
        dropped += 1
        message = render(sections, footer, dropped)
    return message


def nodes(search, name):
    try:
        return [node for node in search[name]["nodes"] if node]
    except (KeyError, TypeError) as error:
        raise DigestError(f"recherche {name} absente de la réponse GraphQL : {error!r}") from error


def build(pulls, runs, repo, now):
    """{title, message, priority, tags, click} pour ntfy, et le texte complet.
    Un champ absent, d'un autre type ou une date d'un autre format devient une
    DigestError : main publie alors quand même un message."""
    try:
        return _build(pulls, runs, repo, now)
    except (KeyError, TypeError, AttributeError, ValueError) as error:
        raise DigestError(f"réponse inattendue : {error!r}") from error


def split_merged(merged):
    """(fusionnées par Renovate lui-même, fusionnées à la main)."""
    automerged, by_hand = [], []
    for pull in merged:
        login = ((pull.get("mergedBy") or {}).get("login") or "").lower()
        (automerged if login in RENOVATE_LOGINS else by_hand).append(pull)
    return automerged, by_hand


def open_line(pull, now):
    notes = []
    if pull.get("autoMergeRequest"):
        notes.append("auto-merge en attente des checks")
    if pull.get("isDraft"):
        notes.append("brouillon")
    note = f" ({', '.join(notes)})" if notes else ""
    return f"- #{pull['number']} {short_title(pull['title'])} : {age(pull['createdAt'], now)}{note}"


def caught_up(run, last_success):
    """Un échec suivi d'un run de push réussi : ce run a redéployé tout ce que
    l'échec n'avait pas fait (diff depuis le dernier succès)."""
    return last_success is not None and parse_time(run["created_at"]) < parse_time(last_success["created_at"])


def run_line(run, last_success):
    when = parse_time(run["created_at"]).strftime("%d/%m %H:%M UTC")
    note = f" (rattrapé par le run #{last_success['run_number']})" if caught_up(run, last_success) else ""
    return f"- run #{run['run_number']} du {when} ({run['event']}){note} : {run.get('display_title', '')} {run['html_url']}"


def priority_of(failed, opened, last_success):
    if any(not caught_up(run, last_success) for run in failed):
        return 4, ["warning"]
    if opened or failed:
        return 3, ["hourglass"]
    return 2, ["white_check_mark"]


def _build(pulls, runs, repo, now):
    merged = nodes(pulls, "merged")
    opened = sorted(nodes(pulls, "open"), key=lambda p: p["createdAt"])
    failed = list(runs["workflow_runs"])
    # Dernier run de push réussi, ajouté par fetch.
    last_success = runs.get("last_success")
    automerged, by_hand = split_merged(merged)

    sections = [
        (f"Déploiements en échec ({len(failed)}) :", [run_line(r, last_success) for r in failed]),
        (f"En attente de relecture ({pulls['open'].get('issueCount') or len(opened)}) :", [open_line(p, now) for p in opened]),
        (f"Fusionnées automatiquement ({len(automerged)}) :", grouped(automerged)),
        (f"Fusionnées à la main ({len(by_hand)}) :", grouped(by_hand)),
    ]
    footer = f"7 derniers jours, PR de Renovate sur {repo} et runs de {DEPLOY_WORKFLOW}."
    merged_total = pulls["merged"].get("issueCount", len(merged))
    if merged_total > len(merged):
        footer += f" {merged_total} PR fusionnées : les {len(merged)} plus récentes seules comptées."
    if not any(lines for _, lines in sections):
        sections = [("Rien cette semaine :", ["aucune PR de Renovate fusionnée ni ouverte, aucun déploiement en échec."])]

    priority, tags = priority_of(failed, opened, last_success)
    return {
        "title": f"Renovate, semaine au {now.strftime('%d/%m')}",
        "message": fit(sections, footer),
        "priority": priority,
        "tags": tags,
        "click": f"https://github.com/{repo}/pulls?q=" + urllib.parse.quote("is:pr is:open author:app/renovate"),
    }, render(sections, footer)


def github(token, path, body=None):
    request = urllib.request.Request(
        API + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
        method="POST" if body is not None else "GET",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def fetch(token, repo, since):
    stamp = since.strftime("%Y-%m-%dT%H:%M:%SZ")
    base = f"repo:{repo} is:pr author:app/renovate"
    answer = github(
        token,
        "/graphql",
        {"query": PULLS_QUERY, "variables": {"merged": f"{base} is:merged merged:>={stamp} sort:updated-desc", "open": f"{base} is:open"}},
    )
    if not isinstance(answer, dict) or answer.get("errors") or "data" not in answer:
        errors = answer.get("errors") if isinstance(answer, dict) else None
        raise DigestError(f"GraphQL : {[e.get('message') for e in errors or [] if isinstance(e, dict)]}")
    query = urllib.parse.urlencode({"status": "failure", "created": f">={stamp}", "per_page": 100})
    runs = github(token, f"/repos/{repo}/actions/workflows/{DEPLOY_WORKFLOW}/runs?{query}")
    query = urllib.parse.urlencode({"status": "success", "event": "push", "per_page": 1})
    latest = github(token, f"/repos/{repo}/actions/workflows/{DEPLOY_WORKFLOW}/runs?{query}")
    if not isinstance(runs, dict) or not isinstance(latest, dict):
        raise DigestError("runs de deploy-docker-app : réponse inattendue")
    runs["last_success"] = (latest.get("workflow_runs") or [None])[0]
    return answer["data"], runs


def publish(url, topic, token, report):
    request = urllib.request.Request(
        url.rstrip("/") + "/",
        data=json.dumps(dict(report, topic=topic)).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        response.read()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo", required=True, help="propriétaire/dépôt")
    args = parser.parse_args(argv)

    now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
    failed = False
    try:
        pulls, runs = fetch(os.environ.get("GITHUB_TOKEN", ""), args.repo, now - datetime.timedelta(days=7))
        report, full = build(pulls, runs, args.repo, now)
    except DigestError as error:
        failed, reason = True, str(error)
    except urllib.error.HTTPError as error:
        failed, reason = True, f"API GitHub : HTTP {error.code}"
    except (OSError, ValueError, http.client.HTTPException) as error:
        failed, reason = True, f"API GitHub injoignable : {type(error).__name__}"
    if failed:
        full = f"Bilan impossible : {reason}. Voir le run de renovate-digest.yaml."
        report = {"title": "Renovate : bilan en échec", "message": full, "priority": 4, "tags": ["warning"]}
        print(f"::error::{reason}")

    print(f"{report['title']}\n\n{full}")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(f"## {report['title']}\n\n```\n{full}\n```\n")

    token = os.environ.get("NTFY_TOKEN", "")
    if not token:
        print("::error::NTFY_TOKEN vide (secret de l'environnement renovate-digest) : rien n'est publié.")
        return 1
    try:
        publish(NTFY_URL, NTFY_TOPIC, token, report)
    except (OSError, ValueError, http.client.HTTPException) as error:
        # Sa classe seule : une erreur d'urllib peut citer la requête.
        print(f"::error::publication sur ntfy en échec : {type(error).__name__}")
        return 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
