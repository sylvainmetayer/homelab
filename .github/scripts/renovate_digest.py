"""Bilan hebdomadaire de Renovate, publié sur ntfy (topic github).

Lu par .github/workflows/renovate-digest.yaml, le lundi après-midi, après le
passage du matin de Renovate (« before 9am on monday », renovate.json) et
les fusions automatiques qui le suivent. Sur les 7 derniers jours :
  - les PR de Renovate fusionnées, automatiquement (fusionnées par Renovate
    lui-même : automerge, platformAutomerge) puis à la main ; les montées
    répétées d'un même paquet (images maison, une par build) regroupées ;
  - les PR de Renovate encore ouvertes, avec leur âge, les plus vieilles
    d'abord ; celles dont l'auto-merge attend les checks sont signalées ;
  - les runs en échec de deploy-docker-app.yaml.

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
# le paquet, sans la version cible.
TITLE_PREFIX = re.compile(r"^(?:chore|fix|build|ci)\(deps\):\s*", re.IGNORECASE)
TITLE_TARGET = re.compile(r"\s+to\s+\S+$")


class DigestError(Exception):
    """Réponse de l'API inexploitable."""


def parse_time(value):
    return datetime.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)


def short_title(title):
    return TITLE_PREFIX.sub("", title).strip()


def package(title):
    return TITLE_TARGET.sub("", short_title(title))


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


def fit(sections, footer):
    """Le message sous MAX_MESSAGE octets : les dernières lignes de la plus
    longue section partent les premières."""
    sections = [(title, list(lines)) for title, lines in sections if lines]
    dropped = 0

    def render():
        parts = [title + "\n" + "\n".join(lines) for title, lines in sections if lines]
        if dropped:
            parts.append(f"... et {dropped} ligne(s) de plus : résumé du run")
        return "\n\n".join(parts + [footer])

    message = render()
    while len(message.encode()) > MAX_MESSAGE and any(lines for _, lines in sections):
        max((lines for _, lines in sections), key=len).pop()
        dropped += 1
        message = render()
    return message


def nodes(search, name):
    try:
        return [node for node in search[name]["nodes"] if node]
    except (KeyError, TypeError) as error:
        raise DigestError(f"recherche {name} absente de la réponse GraphQL : {error!r}") from error


def build(pulls, runs, repo, now):
    """{title, message, priority, tags, click} pour ntfy, et le texte complet."""
    try:
        merged = nodes(pulls, "merged")
        opened = nodes(pulls, "open")
        failed = list(runs["workflow_runs"])
    except (KeyError, TypeError) as error:
        raise DigestError(f"réponse inattendue : {error!r}") from error

    automerged = [p for p in merged if ((p.get("mergedBy") or {}).get("login") or "").lower() in RENOVATE_LOGINS]
    by_hand = [p for p in merged if p not in automerged]
    opened.sort(key=lambda p: p["createdAt"])

    def open_line(pull):
        notes = []
        if pull.get("autoMergeRequest"):
            notes.append("auto-merge en attente des checks")
        if pull.get("isDraft"):
            notes.append("brouillon")
        note = f" ({', '.join(notes)})" if notes else ""
        return f"- #{pull['number']} {short_title(pull['title'])} : {age(pull['createdAt'], now)}{note}"

    def run_line(run):
        when = parse_time(run["created_at"]).strftime("%d/%m %H:%M UTC")
        return f"- run #{run['run_number']} du {when} ({run['event']}) : {run.get('display_title', '')} {run['html_url']}"

    sections = [
        (f"Déploiements en échec ({len(failed)}) :", [run_line(r) for r in failed]),
        (f"En attente de relecture ({len(opened)}) :", [open_line(p) for p in opened]),
        (f"Fusionnées automatiquement ({len(automerged)}) :", grouped(automerged)),
        (f"Fusionnées à la main ({len(by_hand)}) :", grouped(by_hand)),
    ]
    footer = f"7 derniers jours, PR de Renovate sur {repo} et runs de {DEPLOY_WORKFLOW}."
    merged_total = pulls["merged"].get("issueCount", len(merged))
    if merged_total > len(merged):
        footer += f" {merged_total} PR fusionnées : les {len(merged)} plus récentes seules comptées."
    if not any(lines for _, lines in sections):
        sections = [("Rien cette semaine :", ["aucune PR de Renovate fusionnée ni ouverte, aucun déploiement en échec."])]

    if failed:
        priority, tags = 4, ["warning"]
    elif opened:
        priority, tags = 3, ["hourglass"]
    else:
        priority, tags = 2, ["white_check_mark"]
    full = "\n\n".join(title + "\n" + "\n".join(lines) for title, lines in sections if lines) + "\n\n" + footer
    return {
        "title": f"Renovate, semaine au {now.strftime('%d/%m')}",
        "message": fit(sections, footer),
        "priority": priority,
        "tags": tags,
        "click": f"https://github.com/{repo}/pulls?q=" + urllib.parse.quote("is:pr is:open author:app/renovate"),
    }, full


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
    if answer.get("errors") or "data" not in answer:
        raise DigestError(f"GraphQL : {[e.get('message') for e in answer.get('errors') or []]}")
    query = urllib.parse.urlencode({"status": "failure", "created": f">={stamp}", "per_page": 100})
    runs = github(token, f"/repos/{repo}/actions/workflows/{DEPLOY_WORKFLOW}/runs?{query}")
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
    parser.add_argument("--url", default="https://ntfy.sylvain.cloud")
    parser.add_argument("--topic", default="github")
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
        publish(args.url, args.topic, token, report)
    except (OSError, ValueError, http.client.HTTPException) as error:
        # Sa classe seule : une erreur d'urllib peut citer la requête.
        print(f"::error::publication sur ntfy en échec : {type(error).__name__}")
        return 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
