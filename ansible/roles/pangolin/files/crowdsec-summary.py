#!/usr/bin/python3
"""Résumé hebdomadaire de CrowdSec sur ntfy (rôle pangolin, crowdsec-summary.timer).

Alertes locales des 7 derniers jours par scénario et par pays, décisions
actives, correspondances AppSec en détection seule. Priorité haute s'il y a
des correspondances AppSec ou si cscli échoue (le service échoue aussi),
basse sinon. Sans état. Environnement (EnvironmentFile 0600) : NTFY_URL,
NTFY_TOPIC, NTFY_TOKEN ; CROWDSEC_SUMMARY_CSCLI remplace `docker exec
crowdsec cscli` (Molecule). `--dry-run` affiche la charge sans la publier.
"""
import json
import os
import shlex
import subprocess
import sys
import urllib.request
from collections import Counter

APPSEC = ("homelab/appsec-alert-only", "crowdsecurity/appsec-generic-test")


def cscli(*args):
    command = shlex.split(os.environ.get("CROWDSEC_SUMMARY_CSCLI", "docker exec crowdsec cscli"))
    result = subprocess.run(command + [*args, "-o", "json"], capture_output=True, text=True, timeout=120,
                            check=False)
    if result.returncode:
        raise RuntimeError((result.stderr.strip().splitlines() or ["?"])[-1][:200])
    return json.loads(result.stdout or "null") or []


def summary():
    alerts = cscli("alerts", "list", "--since", "168h", "--limit", "0")
    decisions = sum(len(a.get("decisions") or []) for a in cscli("decisions", "list", "--limit", "0"))
    appsec = [a for a in alerts if a.get("scenario") in APPSEC]
    others = [a for a in alerts if a.get("scenario") not in APPSEC]
    lines = [f"  {s} {n}" for s, n in Counter(a.get("scenario") or "?" for a in others).most_common(8)]
    countries = Counter((a.get("source") or {}).get("cn") or "??" for a in others).most_common(8)
    lines = ["Scénarios :", *lines, "Pays : " + ", ".join(f"{c} {n}" for c, n in countries)] if others else []
    lines.append(f"Décisions actives : {decisions}")
    if appsec:
        lines.append(f"AppSec (détection seule) : {len(appsec)}, à regarder (docs/runbooks/crowdsec.md)")
    title = f"CrowdSec 7 j : {len(others)} alertes, {decisions} décisions actives, AppSec {len(appsec)}"
    return title, "\n".join(lines), 4 if appsec else 2


def main():
    try:
        title, text, priority, failed = *summary(), False
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        title, text, priority, failed = "CrowdSec : résumé impossible", f"cscli : {error}", 4, True
    payload = {"topic": os.environ.get("NTFY_TOPIC", ""), "title": title, "message": text,
               "priority": priority, "tags": ["shield"]}
    if "--dry-run" in sys.argv:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return int(failed)
    request = urllib.request.Request(os.environ["NTFY_URL"], data=json.dumps(payload).encode(), method="POST",
                                     headers={"Authorization": f"Bearer {os.environ['NTFY_TOKEN']}",
                                              "Content-Type": "application/json"})
    try:
        urllib.request.urlopen(request, timeout=30).close()
    except OSError as error:  # sa classe seule : le message peut citer la requête
        sys.exit(f"publication ntfy en échec : {type(error).__name__}")
    print(title)
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
