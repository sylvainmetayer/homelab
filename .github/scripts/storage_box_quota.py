"""Remplissage de la Storage Box des sauvegardes, chaque semaine.

Lu par .github/workflows/storage-box-quota.yaml : l'API Hetzner
(GET /v1/storage_boxes?name=…, jeton de projet en lecture seule) donne
l'espace occupé (données et snapshots, stats.size) et la taille de l'offre
(storage_box_type.size). Au-delà du seuil, le run échoue et le moniteur push
« Storage Box » d'Uptime Kuma passe « down » avec le pourcentage ; en
dessous, il reçoit « up ». Une API injoignable ou une réponse inattendue
pousse « down » aussi : un contrôle muet ne protège de rien.

Le jeton et l'URL push arrivent par l'environnement, jamais affichés.
"""

import argparse
import http.client
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.hetzner.com/v1/storage_boxes"
GIB = 1024**3


class QuotaError(Exception):
    """Réponse de l'API inexploitable."""


def usage(payload, name):
    """(occupé, taille de l'offre, détail) de la Storage Box `name`."""
    try:
        boxes = [box for box in payload["storage_boxes"] if box["name"] == name]
    except (KeyError, TypeError) as error:
        raise QuotaError(f"liste storage_boxes absente ou invalide dans la réponse de l'API : {error!r}") from error
    if len(boxes) != 1:
        raise QuotaError(f"{len(boxes)} Storage Box nommée(s) {name!r} dans la réponse de l'API")
    box = boxes[0]
    try:
        used = int(box["stats"]["size"])
        quota = int(box["storage_box_type"]["size"])
        data = int(box["stats"].get("size_data", 0))
        snapshots = int(box["stats"].get("size_snapshots", 0))
    except (KeyError, TypeError, ValueError) as error:
        raise QuotaError(f"champ absent ou invalide dans la réponse de l'API : {error!r}") from error
    if quota <= 0:
        raise QuotaError(f"taille d'offre invalide : {quota}")
    detail = (
        f"{used / GIB:.0f} Gio sur {quota / GIB:.0f} Gio "
        f"(données {data / GIB:.0f} Gio, snapshots {snapshots / GIB:.0f} Gio)"
    )
    return used, quota, detail


def evaluate(payload, name, threshold):
    """(status Uptime Kuma, message) pour un seuil en pourcentage."""
    used, quota, detail = usage(payload, name)
    percent = 100 * used / quota
    status = "down" if percent >= threshold else "up"
    return status, f"{percent:.1f} % occupés (seuil {threshold:g} %) : {detail}"


def fetch(token, name):
    url = API + "?" + urllib.parse.urlencode({"name": name})
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def push(url, status, msg):
    query = urllib.parse.urlencode({"status": status, "msg": msg, "ping": ""})
    separator = "&" if "?" in url else "?"
    with urllib.request.urlopen(url + separator + query, timeout=30) as response:
        response.read()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--name", default="backups")
    parser.add_argument("--threshold", type=float, default=80)
    args = parser.parse_args(argv)

    token = os.environ.get("HCLOUD_READONLY_TOKEN", "")
    push_url = os.environ.get("PUSH_URL", "")
    if not token:
        status, msg = "down", "HCLOUD_READONLY_TOKEN vide (secret de l'environnement storage-box-quota)"
    else:
        try:
            status, msg = evaluate(fetch(token, args.name), args.name, args.threshold)
        except QuotaError as error:
            status, msg = "down", str(error)
        except urllib.error.HTTPError as error:
            status, msg = "down", f"API Hetzner : HTTP {error.code}"
        except (OSError, ValueError, http.client.HTTPException) as error:
            # Le message d'une erreur réseau peut citer l'URL : sa classe seule.
            status, msg = "down", f"API Hetzner injoignable : {type(error).__name__}"

    print(f"{'::error::' if status == 'down' else ''}Storage Box {args.name} : {msg}")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(f"Storage Box `{args.name}` : {msg}\n")

    if push_url:
        try:
            push(push_url, status, msg)
        except (OSError, ValueError, http.client.HTTPException) as error:
            # Sa classe seule : le message peut citer l'URL push, un secret.
            print(f"::error::push vers Uptime Kuma en échec : {type(error).__name__}")
            return 1
    else:
        print("::warning::PUSH_URL vide : rien n'est poussé.")
    return 1 if status == "down" else 0


if __name__ == "__main__":
    sys.exit(main())
