#!/usr/bin/python3
"""Résumé hebdomadaire de CrowdSec sur ntfy (rôle pangolin, crowdsec-summary.timer).

Alertes locales des 7 derniers jours par scénario et par pays, décisions
actives, correspondances AppSec en détection seule. Priorité haute s'il y a
des correspondances AppSec ou si cscli échoue (le service échoue aussi),
basse sinon. Sans état. Environnement (EnvironmentFile 0600) : NTFY_URL,
NTFY_TOPIC, NTFY_TOKEN ; CROWDSEC_SUMMARY_CSCLI remplace `docker exec
crowdsec cscli` (Molecule). `--dry-run` affiche la charge sans la publier.
"""
import http.client
import json
import os
import shlex
import subprocess
import sys
import urllib.error
import urllib.request
from collections import Counter

APPSEC = ("homelab/appsec-alert-only", "crowdsecurity/appsec-generic-test")
TOP = 8


def plural(count, word):
    return f"{count} {word}{'s' if count > 1 else ''}"


def cscli(*args):
    command = shlex.split(os.environ.get("CROWDSEC_SUMMARY_CSCLI", "docker exec crowdsec cscli"))
    result = subprocess.run(command + [*args, "-o", "json"], capture_output=True, text=True, timeout=120,
                            check=False)
    if result.returncode:
        raise RuntimeError((result.stderr.strip().splitlines() or ["?"])[-1][:200])
    items = json.loads(result.stdout or "null") or []
    # Une réponse d'une autre forme doit publier l'échec, pas planter plus loin.
    if not isinstance(items, list) or not all(isinstance(item, dict) for item in items):
        raise ValueError("une liste d'alertes était attendue")
    return items


def summary():
    alerts = cscli("alerts", "list", "--since", "168h", "--limit", "0")
    decisions = sum(len(a.get("decisions") or []) for a in cscli("decisions", "list", "--limit", "0"))
    appsec = [a for a in alerts if a.get("scenario") in APPSEC]
    others = [a for a in alerts if a.get("scenario") not in APPSEC]
    scenarios = Counter(a.get("scenario") or "?" for a in others)
    countries = Counter((a.get("source") or {}).get("cn") or "??" for a in others).most_common(TOP)
    lines = []
    if others:
        lines = ["Scénarios :", *(f"  {s} {n}" for s, n in scenarios.most_common(TOP))]
        if len(scenarios) > TOP:
            lines.append(f"  … et {plural(len(scenarios) - TOP, 'autre')}")
        lines.append("Pays : " + ", ".join(f"{c} {n}" for c, n in countries))
    lines.append(f"Décisions actives : {decisions}")
    if appsec:
        lines.append(f"AppSec (détection seule) : {len(appsec)}, à regarder (docs/runbooks/crowdsec.md)")
    title = (f"CrowdSec 7 j : {plural(len(others), 'alerte')}, {plural(decisions, 'décision')} "
             f"{'actives' if decisions > 1 else 'active'}, AppSec {len(appsec)}")
    return title, "\n".join(lines), 4 if appsec else 2


def main():
    if sys.argv[1:] not in ([], ["--dry-run"]):
        sys.exit("usage : crowdsec-summary [--dry-run]")
    try:
        title, text, priority, failed = *summary(), False
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        title, text, priority, failed = ("CrowdSec : résumé impossible",
                                         f"cscli : {error}\nsudo docker ps --filter name=crowdsec ; "
                                         "docs/runbooks/crowdsec.md", 4, True)
    url, topic, token = (os.environ.get(key, "") for key in ("NTFY_URL", "NTFY_TOPIC", "NTFY_TOKEN"))
    payload = {"topic": topic, "title": title, "message": text, "priority": priority, "tags": ["shield"]}
    if sys.argv[1:] == ["--dry-run"]:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return int(failed)
    if not (url and topic and token):
        sys.exit("NTFY_URL, NTFY_TOPIC ou NTFY_TOKEN vide : rien n'est publié.")
    request = urllib.request.Request(url, data=json.dumps(payload).encode(), method="POST",
                                     headers={"Authorization": f"Bearer {token}",
                                              "Content-Type": "application/json"})
    try:
        urllib.request.urlopen(request, timeout=30).close()
    except urllib.error.HTTPError as error:
        sys.exit(f"publication ntfy en échec : HTTP {error.code}")
    except (OSError, ValueError, http.client.HTTPException) as error:
        # Sa classe seule : le message d'une erreur réseau peut citer la requête.
        sys.exit(f"publication ntfy en échec : {type(error).__name__}")
    print(title)
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
