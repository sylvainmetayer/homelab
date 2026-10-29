"""Vulnérabilités CRITICAL corrigeables de l'analyse Trivy hebdomadaire, sur ntfy.

Lu par le job `notify` de .github/workflows/trivy.yaml : chaque job d'image y
dépose son rapport JSON (`<nom de l'image>.json`, déjà filtré par
--severity HIGH,CRITICAL --ignore-unfixed). Seules les CRITICAL restent,
regroupées par image avec la version qui les corrige ; sans aucune, rien
n'est publié. Le message part sur le topic `github` de ntfy.sylvain.cloud
(JSON sur `/`, le chemin ouvert sans SSO de tofu/pangolin_config), le
détail reste dans l'onglet Security (code scanning).

Le jeton (NTFY_TOKEN) arrive par l'environnement, jamais affiché.

    python -I .github/scripts/trivy_critical.py --dry-run <dossier des rapports>
"""

import argparse
import http.client
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

NTFY_URL = "https://ntfy.sylvain.cloud/"
# Celui de tout ce que publie la CI (producteur github du rôle ntfy).
TOPIC = "github"
# ntfy refuse (ou change en pièce jointe, désactivées ici) un message de plus
# de 4096 octets : le reste est résumé en une ligne.
MAX_MESSAGE_BYTES = 3500


class ReportError(Exception):
    """Rapport Trivy illisible."""


def critical_fixed(report):
    """[(id, paquet, version installée, version corrigée)] d'un rapport, sans doublon.

    Une même CVE revient dans plusieurs cibles (couche OS, jar…) : une fois
    par paquet et version.
    """
    found = set()
    try:
        for result in report.get("Results") or []:
            for vuln in result.get("Vulnerabilities") or []:
                if vuln.get("Severity") != "CRITICAL" or not vuln.get("FixedVersion"):
                    continue
                found.add((vuln["VulnerabilityID"], vuln["PkgName"], vuln.get("InstalledVersion") or "?", vuln["FixedVersion"]))
        # Dans le try : un champ à null ne se trie pas avec des chaînes.
        return sorted(found)
    except (AttributeError, KeyError, TypeError) as error:
        raise ReportError(f"rapport Trivy inattendu : {error!r}") from error


def collect(directory):
    """{nom de l'image: [vulnérabilités]} des images qui en ont au moins une."""
    images = {}
    paths = sorted(Path(directory).glob("*.json"))
    if not paths:
        raise ReportError(f"aucun rapport dans {directory}")
    for path in paths:
        try:
            report = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            raise ReportError(f"{path.name} illisible : {error!r}") from error
        vulns = critical_fixed(report)
        if vulns:
            images[path.stem] = vulns
    return images


def message(images, link):
    """Charge JSON de la publication ntfy, ou None sans vulnérabilité."""
    if not images:
        return None
    # Des CVE, pas des lignes : une même CVE touche souvent plusieurs paquets.
    total = sum(len({vuln[0] for vuln in vulns}) for vulns in images.values())
    lines = []
    for name in sorted(images):
        lines.append(name)
        lines.extend(f"  {vid} {pkg} {installed} → {fixed}" for vid, pkg, installed, fixed in images[name])
    body = ""
    for index, line in enumerate(lines):
        candidate = body + line + "\n"
        if len(candidate.encode("utf-8")) > MAX_MESSAGE_BYTES:
            body += f"… et {len(lines) - index} lignes de plus (onglet Security)\n"
            break
        body = candidate
    plural = "s" if len(images) > 1 else ""
    return {
        "topic": TOPIC,
        "title": f"Trivy : {total} CVE critique{'s' if total > 1 else ''} corrigeable{'s' if total > 1 else ''}, {len(images)} image{plural}",
        "message": body.rstrip("\n"),
        "priority": 4,
        "tags": ["rotating_light"],
        "click": link,
    }


def publish(token, payload):
    request = urllib.request.Request(
        NTFY_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        response.read()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("reports", help="dossier des rapports JSON, un par image")
    parser.add_argument("--dry-run", action="store_true", help="affiche le message sans le publier")
    args = parser.parse_args(argv)

    server = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
    repository = os.environ.get("GITHUB_REPOSITORY", "sylvainmetayer/homelab")
    link = f"{server}/{repository}/security/code-scanning?query=is%3Aopen+severity%3Acritical"
    try:
        payload = message(collect(args.reports), link)
    except ReportError as error:
        print(f"::error::{error}")
        return 1

    if payload is None:
        print("Aucune vulnérabilité CRITICAL corrigeable : rien n'est publié.")
        return 0
    # Le titre seul : le dépôt est public, le détail reste sur ntfy et dans l'onglet Security.
    print(payload["title"])
    if args.dry_run:
        return 0

    token = os.environ.get("NTFY_TOKEN", "")
    if not token:
        print("::error::NTFY_TOKEN vide (secret de l'environnement ntfy-github)")
        return 1
    try:
        publish(token, payload)
    except urllib.error.HTTPError as error:
        print(f"::error::publication ntfy en échec : HTTP {error.code}")
        return 1
    except (OSError, ValueError, http.client.HTTPException) as error:
        # Sa classe seule : le message d'une erreur réseau peut citer la requête.
        print(f"::error::publication ntfy en échec : {type(error).__name__}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
