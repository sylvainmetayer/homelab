"""Alerte du plan nocturne de tofu/pangolin_config (.github/workflows/plan-pangolin-config.yaml).

Lu par le job `notify` : il reçoit le résultat du job `plan` (RESULT), le code
de sortie de `tofu plan -detailed-exitcode` (PLAN_RC : 0 vide, 2 non vide, vide
si le plan n'a pas tourné) et son décompte (PLAN_SUMMARY, « Plan: A to add, B to
change, C to destroy. »). Le dépôt est public : seuls ce code et ces trois
nombres sortent du job `plan`, jamais le texte du plan, et rien d'autre n'est
affiché ici que le titre.

- plan vide (0) : « up » au moniteur Uptime Kuma « Plan nocturne », pas de message ;
- plan non vide (2) : « up » aussi (le contrôle a tourné) et un message ntfy
  (topic `github`, jeton NTFY_TOKEN) avec le décompte ;
- tout le reste (tunnel OLM, init, API, délai dépassé, annulation) : « down » et
  un message ntfy.

Le jeton ntfy et l'URL push arrivent par l'environnement, jamais affichés.
    python -I .github/scripts/plan_drift_notify.py --dry-run
"""

import argparse
import http.client
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

NTFY_URL = "https://ntfy.sylvain.cloud/"
# Celui de tout ce que publie la CI (producteur github du rôle ntfy).
TOPIC = "github"
SUMMARY = re.compile(r"^Plan: (\d+) to add, (\d+) to change, (\d+) to destroy\.$")


def decide(result, rc, summary):
    """(statut Uptime Kuma, message, charge ntfy ou None)."""
    if result == "success" and rc == "0":
        return "up", "Aucune dérive", None
    if result == "success" and rc == "2":
        found = SUMMARY.match(summary)
        counts = f"{found[1]} à ajouter, {found[2]} à modifier, {found[3]} à détruire" if found else "décompte illisible"
        title = f"pangolin_config : le plan n'est pas vide ({counts})"
        return "up", title, {
            "topic": TOPIC,
            "title": title,
            "message": "Dérive ou écart code/réalité. Détail : tofu plan à la main (skill pangolin-config-plan).",
            "priority": 4,
            "tags": ["warning"],
        }
    title = f"pangolin_config : le plan nocturne a échoué (job {result or 'inconnu'}, code {rc or 'aucun'})"
    return "down", title, {
        "topic": TOPIC,
        "title": title,
        "message": "Tunnel OLM, init, API Pangolin ou délai : voir le run (aucun texte de plan n'y est publié).",
        "priority": 4,
        "tags": ["rotating_light"],
    }


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


# Aucune redirection suivie : urllib renverrait le jeton ntfy à la cible, et le
# 200 de sa page d'arrivée compterait comme une publication réussie.
_OPENER = urllib.request.build_opener(_NoRedirect)


def publish(token, payload):
    request = urllib.request.Request(
        NTFY_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    with _OPENER.open(request, timeout=30) as response:
        response.read()


def push(url, status, msg):
    query = urllib.parse.urlencode({"status": status, "msg": msg, "ping": ""})
    with _OPENER.open(f"{url}?{query}", timeout=30) as response:
        response.read()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true", help="affiche le titre sans rien envoyer")
    args = parser.parse_args(argv)

    status, msg, payload = decide(
        os.environ.get("RESULT", ""), os.environ.get("PLAN_RC", ""), os.environ.get("PLAN_SUMMARY", "")
    )
    print(msg)
    if args.dry_run:
        return 0

    rc = 0
    push_url = os.environ.get("PUSH_URL", "")
    token = os.environ.get("NTFY_TOKEN", "")
    # Chaque envoi à part : un jeton ntfy mort ne doit pas taire le moniteur, ni
    # l'inverse. Sa classe seule dans l'erreur : le message d'une erreur réseau
    # peut citer la requête, donc l'URL push ou le jeton.
    sends = [("Uptime Kuma", push_url, lambda: push(push_url, status, msg))]
    if payload:
        sends.append(("ntfy", token, lambda: publish(token, payload)))
    for name, secret, send in sends:
        if not secret:
            print(f"::error::{name} : secret vide (environnement tofu-drift)")
            rc = 1
            continue
        try:
            send()
        except urllib.error.HTTPError as error:
            print(f"::error::envoi {name} en échec : HTTP {error.code}")
            rc = 1
        except (OSError, ValueError, http.client.HTTPException) as error:
            print(f"::error::envoi {name} en échec : {type(error).__name__}")
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
